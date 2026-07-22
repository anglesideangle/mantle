mantleModule: pkgs: args:
let
  # Creates a new repart definition containing instructions for systemd-repart
  # to copy from the specified original `partition`. The resulting partition
  # will have the same contents and UUID as the original.
  copyFromRepartSplit = config: partition: {
    repartConfig =
      removeAttrs partition.repartConfig [
        "Format"
        "Verity"
        "VerityMatchKey"
      ]
      // {
        CopyBlocks = "${config.system.build.image}/${config.image.baseName}.${partition.repartConfig.SplitName}.raw";
        UUID = pkgs.runCommand "get-uuid" { } ''
          ${pkgs.jq}/bin/jq -r \
            '.[] | select(.label == "${partition.repartConfig.Label}") | .uuid' \
            "${config.system.build.image}/repart-output.json"" \
            > $out
        '';
      };
  };

  baseConfig = import "${pkgs.path}/nixos/lib/eval-config.nix" (
    {
      system = null;
      modules = (args.modules or [ ]) ++ [ mantleModule ];
    }
    // removeAttrs args [ "modules" ]
  );

  fullConfig = baseConfig.extendModules {
    modules = [
      (
        { config, lib, ... }:
        let
          defs = config.system.build._partitionDefs;
        in
        {
          image.repart.partitions = lib.mkForce {
            "00-esp" = defs.esp;
            "10-store-verity" = defs.store-verity;
            "11-store" = defs.store;
            "20-store-B-verity" = defs.empty-store-verity;
            "21-store-B" = defs.empty-store;
            "30-var" = defs.var;
          };
        }
      )
    ];
  };

  updateConfig = baseConfig.extendModules {
    modules = [
      (
        { config, lib, ... }:
        let
          defs = config.system.build._partitionDefs;
        in
        {
          image.repart.partitions = lib.mkForce {
            "00-esp" = defs.esp;
            "10-store-verity" = defs.store-verity;
            "11-store" = defs.store;
          };
        }
      )
    ];
  };

  installerConfig = baseConfig.extendModules {
    modules = [
      (
        { config, lib, ... }:
        let
          defs = config.system.build._partitionDefs;
          mkInstaller = config.system.build._mkInstaller;
        in
        {
          environment.systemPackages = [
            (mkInstaller "mantle-install" {
              "00-esp" = defs.esp-installer-copy;
              "10-store-verity" = defs.store-verity-copy;
              "11-store" = defs.store-installer-copy;
            })
          ];

          image.repart = {
            name = "${config.system.image.id}-installer";
            partitions = lib.mkForce {
              "00-esp" = defs.esp;
              "10-store-verity" = defs.store-verity;
              "11-store" = defs.store;
              "20-installer" = defs.var-installer;
            };
          };
        }
      )
    ];
  };

  hostUrl = "root@${updateConfig.config.networking.hostName}";

  flash-to-device =
    let
      cfg = fullConfig.extendModules {
        modules = [
          (
            { config, lib, ... }:
            let
              defs = config.system.build._partitionDefs;
              mkInstaller = config.system.build._mkInstaller;
            in
            {
              system.build._flash-to-device = mkInstaller "flash-to-device" {
                "00-esp" = copyFromRepartSplit config defs.esp;
                "10-store-verity" = copyFromRepartSplit config defs.store-verity;
                "11-store" = copyFromRepartSplit config defs.store;
                "20-store-B-verity" = defs.empty-store-verity;
                "21-store-B" = defs.empty-store;
                "30-var" = defs.var;
              };
            }
          )
        ];
      };
    in
    cfg.config.system.build._flash-to-device;

  flash-installer-to-device =
    let
      cfg = installerConfig.extendModules {
        modules = [
          (
            { config, lib, ... }:
            let
              defs = config.system.build._partitionDefs;
              mkInstaller = config.system.build._mkInstaller;
            in
            {
              system.build._flash-installer-to-device = mkInstaller "flash-to-device" {
                "00-esp" = copyFromRepartSplit config defs.esp;
                "10-store-verity" = copyFromRepartSplit config defs.store-verity;
                "11-store" = copyFromRepartSplit config defs.store;
              };
            }
          )
        ];
      };
    in
    cfg.config.system.build._flash-installer-to-device;

  updatePayload =
    let
      updateBase = updateConfig.config.image.baseName;
      version = updateConfig.config.system.image.version;
      ukiFile = updateConfig.config.system.boot.loader.ukiFile;
    in
    pkgs.runCommand "update-${version}"
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
    # The in-image helper from modules/networking.nix is called
    # `mount-overlay`.
    text = ''
      set -euo pipefail
      ssh "${hostUrl}" "mount-overlay"
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
      scp -r "${updatePayload}" "${hostUrl}:/var/updates/"
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
        copy --to "ssh://${hostUrl}?remote-store=/var/nix/upper" "${updateToplevel}"
      ssh "${hostUrl}" '
        set -euo pipefail
        mount-overlay
        ${updateToplevel}/bin/switch-to-configuration test
      '
    '';
  };

  fullImage = fullConfig.config.system.build.image;
  updateImage = updateConfig.config.system.build.image;
  installerImage = installerConfig.config.system.build.image;

  updateToplevel = updateConfig.config.system.build.toplevel;
  ukiDrv = updateConfig.config.system.build.uki;
in
{
  inherit
    fullImage
    installerImage
    updateImage

    updatePayload
    updateToplevel

    flash-to-device
    flash-installer-to-device

    activate-overlay
    deactivate-overlay
    clear-overlay
    deploy-update
    deploy-overlay
    ;
}
