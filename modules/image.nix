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
          SplitName = "esp";
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
        CopyBlocks = "auto";
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

  mkInstaller = import ../lib/mk-installer.nix { inherit lib pkgs utils; };

  # Build a flash partition def that 1:1 copies a partition's split artifact
  # (produced by a separate image build) onto the target disk. The split
  # artifact's filename is derived from the source partition's `SplitName`.
  /**
    # Arguments
    - `config`: The partition
    - `source`:
    - `baseName`:
  */
  copyFromSplit = config: partition: {
    repartConfig = builtins.removeAttrs partition.repartConfig [ "Format" ] // {
      CopyBlocks = "${config.system.build.image}/${config.image.baseName}.${partition.repartConfig.SplitName}.raw";
    };
  };

  hostUrl = "root@${config.networking.hostName}";

  updateVersion = config.system.image.version;
  updateImage = config.system.build.finalImage;
  updateBase = config.image.baseName;
  updateToplevel = config.system.build.toplevel;
  ukiDrv = config.system.build.uki;
  ukiFile = config.system.boot.loader.ukiFile;

in
{
  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  config = mkIf cfg.enable {
    boot.uki.tries = 2;

    image.repart = {
      verityStore = {
        enable = true;
        partitionIds = {
          esp = cfg.esp.id;
          store-verity = cfg.store-verity.id;
          store = cfg.store.id;
        };
        ukiPath = "/EFI/Linux/${config.system.boot.loader.ukiFile}";
      };
      # name = "${config.system.image.id}-update-${config.system.image.version}";
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

    specialization = {
      # Full image to be flashed onto ssds directly.
      full.configuration.config.image.repart = {
        # name = config.system.image.id;
        # split = true;
        partitions = lib.mkForce {
          "00-esp" = partitions.esp;
          "10-store-A-verity" = partitions.store-verity;
          "11-store-A" = partitions.store;
          "20-store-B-verity" = partitions.empty-store-verity;
          "21-store-B" = partitions.empty-store;
          "30-var" = partitions.var;
        };
      };

      # Installer to be flashed on a usb drive to install a full image
      installer.configuration.config = {
        environment.systemPackages = [
          (mkInstaller "mantle-install" {
            "00-esp" = partitions.esp-installer-copy;
            "10-store-verity" = partitions.store-verity-copy;
            "11-store" = partitions.store-installer-copy;
          })
        ];

        image.repart = {
          name = "${config.system.image.id}-installer";
          compression = {
            enable = true;
            algorithm = "zstd";
          };
          partitions = lib.mkForce {
            "00-esp" = partitions.esp;
            "10-store-verity" = partitions.store-verity;
            "11-store" = partitions.store;
            "20-installer" = partitions.var-installer;
          };
        };
      };
    };

    system.build = {
      flash-to-device =
        let
          flashConfig = config.specialization.full.configuration.config;
          esp-flash = copyFromSplit flashConfig partitions.esp;
          store-verity-flash = copyFromSplit flashConfig partitions.store-verity;
          store-flash = copyFromSplit flashConfig partitions.store;
        in
        mkInstaller "flash-to-device" {
          "00-esp" = esp-flash;
          "10-store-A-verity" = store-verity-flash;
          "11-store-A" = store-flash;
          "20-store-B-verity" = partitions.empty-store-verity;
          "21-store-B" = partitions.empty-store;
          "30-var" = partitions.var;
        };

      flash-installer-to-device =
        let
          installerConfig = config.specialization.installer.configuration.config;
          esp-installer-flash = copyFromSplit installerConfig partitions.esp;
          store-verity-installer-flash = copyFromSplit installerConfig partitions.store-verity;
          store-installer-flash = copyFromSplit installerConfig partitions.store;
        in
        mkInstaller "flash-installer-to-device" {
          "00-esp" = esp-installer-flash;
          "10-store-verity" = store-verity-installer-flash;
          "11-store" = store-installer-flash;
        };

      updatePayload =
        pkgs.runCommand "update-${updateVersion}"
          {
            nativeBuildInputs = [ pkgs.zstd ];
          }
          ''
            mkdir -p $out
            cp \
              "${updateImage}/${updateBase}.store.raw.zst" \
              "${updateImage}/${updateBase}.store-verity.raw.zst" \
              $out
            zstd -1 "${ukiDrv}/${ukiFile}" -o "$out/${ukiFile}.zst"
          '';

      activate-overlay = pkgs.writeShellApplication {
        name = "activate-overlay";
        runtimeInputs = [ pkgs.openssh ];
        text = ''
          set -euo pipefail
          ssh "${hostUrl}" "activate-overlay"
        '';
      };

      deactivate-overlay = pkgs.writeShellApplication {
        name = "deactivate-overlay";
        runtimeInputs = [ pkgs.openssh ];
        text = ''
          set -euo pipefail
          ssh "${hostUrl}" "deactivate-overlay"
        '';
      };

      clear-overlay = pkgs.writeShellApplication {
        name = "clear-overlay";
        runtimeInputs = [ pkgs.openssh ];
        text = ''
          set -euo pipefail
          ssh "${hostUrl}" "rm -rf /var/nix/upper"
        '';
      };

      deploy-update = pkgs.writeShellApplication {
        name = "deploy-update";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.openssh
        ];
        text = ''
          set -euo pipefail
          scp -r "${config.system.build.updatePayload}" "${hostUrl}:/var/updates/"
          ssh "${hostUrl}" '
            set -eu pipefail
            systemd-sysupdate update
            rm -rf /var/nix/upper
            systemctl reboot
          '
        '';
      };

      deploy-overlay = pkgs.writeShellApplication {
        name = "deploy-overlay";
        runtimeInputs = [
          pkgs.nix
          pkgs.openssh
        ];
        text = ''
          set -euo pipefail
          nix \
            --extra-experimental-features "nix-command flakes" \
            copy --to "ssh://${hostUrl}:/var/nix/upper" "${updateToplevel}"
          ssh "${hostUrl}" '
            set -euo pipefail
            activate-overlay
            ${updateToplevel}/bin/switch-to-configuration test
          '
        '';
      };
    };

  };
}
