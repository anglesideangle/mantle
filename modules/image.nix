{
  lib,
  pkgs,
  config,
  modulesPath,
  utils,
  ...
}:
with lib;
let
  cfg = config.partitions;
  store-label = "${cfg.store.label-prefix}_${config.system.image.version}";
  store-verity-label = "${cfg.store-verity.label-prefix}_${config.system.image.version}";

  format = pkgs.formats.ini { listsAsDuplicateKeys = true; };

  partitions =
    let
      efiArch = config.nixpkgs.hostPlatform.efiArch;
      bootLocation = "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI";
    in
    rec {
      esp = {
        repartConfig = {
          Type = "esp";
          Label = "boot";
          Format = cfg.esp.format;
          SizeMinBytes = cfg.esp.size;
          SizeMaxBytes = cfg.esp.size;
        };
        contents.${bootLocation}.source = "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
      };

      esp-installer-copy.repartConfig = esp.repartConfig // {
        CopyBlocks = "auto";
      };

      store = {
        storePaths = [ config.system.build.toplevel ];
        repartConfig = {
          Label = store-label;
          Format = cfg.store.format;
          ReadOnly = "yes";
          SplitName = "store";
          SizeMinBytes = cfg.store.size;
          SizeMaxBytes = cfg.store.size;
        };
      };

      store-installer-copy.repartConfig = store.repartConfig // {
        CopyBlocks = "auto";
      };

      store-verity.repartConfig = {
        Label = store-verity-label;
        SplitName = "store-verity";
      };

      store-verity-copy.repartConfig = store-verity.repartConfig // {
        CopyBlocks = "auto"; # TODO maybe don't inherit store-verity because of stuff in repart-verity-store
      };

      empty-store.repartConfig = {
        inherit (store.repartConfig)
          Type
          SizeMinBytes
          SizeMaxBytes
          ;
        Label = "_empty";
        Minimize = "off";
      };

      empty-store-verity.repartConfig = {
        inherit (store-verity.repartConfig) Type;
        Label = "_empty";
        Minimize = "off";
      };

      var.repartConfig = {
        Type = "var";
        Format = cfg.var.format;
        Label = cfg.var.label;
        Minimize = "off";
        GrowFileSystem = "yes";
        Weight = "100";
        FactoryReset = "yes";
      };

    };

in
{
  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  boot.uki.tries = 2;

  config.image.repart = mkIf cfg.enable {
    verityStore = {
      enable = true;
      partitionIds = {
        esp = cfg.esp.id;
        store-verity = cfg.store-verity.id;
        store = cfg.store.id;
      };
      ukiPath = "/EFI/Linux/${config.system.boot.loader.ukiFile}";
    };
  };

  # FULL (a/b + a/b-verity + uki/esp + empty var)
  # UPDATE (just store + verity + uki)
  # INSTALLER (from update + var with installer script ->) installer script contains FULL (copy variant) (copy a, copy a-verity, new empty b, b-verity, new empty var)
  config.specialization = mkIf cfg.enable {
    # Full image to be flashed onto ssds directly
    full.configuration.config.image.repart = {
      name = config.system.image.id;
      split = false;
      partitions = {
        "00-esp" = partitions.esp;
        "10-store-A-verity" = partitions.store-verity;
        "11-store-A" = partitions.store;
        "20-store-B-verity" = partitions.empty-store-verity;
        "21-store-B" = partitions.empty-store;
        "30-var" = partitions.var;
      };
    };

    # Update payload
    update.configuration.config.image.repart = {
      name = "${config.system.image.id}-update-${config.system.image.version}";
      split = true;
      compression = {
        enable = true;
        algorithm = "zstd";
      };
      partitions = {
        "00-store-verity" = partitions.store-verity;
        "01-store" = partitions.store;
      };
    };

    # Installer to be flashed on a usb drive to install a full image
    installer.configuration.config =
      let
        # The installer command is self-contained and has no closure so that it can
        # be copied to a separate partition from the main store partition on the
        # installer image, which will be 1:1 copied with `CopyBlocks=auto`.
        mkInstaller =
          partitions:
          let
            repartCfg = utils.systemdUtils.lib.definitions "repart.d" format (
              lib.mapAttrs (_name: value: { Partition = value.repartConfig; }) partitions
            );
            repartDefs = lib.concatStringsSep "\n" (
              lib.mapAttrsToList (filename: _v: ''
                cat <<'REPART_CONF_EOF' "$defs/${filename}.conf"
                ${builtins.readFile "${repartCfg}/${filename}.conf"}
                REPART_CONF_EOF
              '') partitions
            );
          in
          pkgs.writeShellScriptBin "mantle-install" ''
            set -euo pipefail

            target="''${1:?usage: mantle-install <target-disk>}"

            defs=$(mktemp -d)
            trap 'rm -rf "$defs"' EXIT

            ${repartDefs}

            systemd-repart \
              # --copy-from \ TODO
              --definitions="$defs" \
              --empty=force \
              --dry-run=no \
              "$target"
          '';
      in
      {
        environment.systemPackages = [
          (mkInstaller [
            partitions.esp-installer-copy
            partitions.store-verity-copy
            partitions.store-installer-copy
          ])
        ];

        image.repart = {
          name = "${config.system.image.id}-installer";
          compression = {
            enable = true;
            algorithm = "zstd";
          };
          partitions = {
            "00-esp" = partitions.esp;
            "10-store-verity" = partitions.store-verity;
            "11-store" = partitions.store;
            "20-installer" = partitions.var-installer;
          };
        };
      };
  };
}
