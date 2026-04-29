let
  mkInstallScript =
    {
      name,
      pkgs,
      payload,
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.zstd
      ];
      text = ''
        set -euo pipefail

        if [ "$#" -ne 2 ] || [ "$1" != "--device" ]; then
          echo "usage: $0 --device /dev/<disk>" >&2
          exit 2
        fi

        device="$2"

        if [ ! -b "$device" ]; then
          echo "$device is not a block device" >&2
          exit 2
        fi

        echo "About to flash ${payload} to $device."
        printf "This will erase all data on %s. Continue? [y/N] " "$device"
        read -r answer

        case "$answer" in
          y|Y|yes|YES)
            ;;
          *)
            echo "Aborted"
            exit 1
            ;;
        esac

        zstd -dc ${payload} | dd of="$device" bs=64M conv=fsync status=progress
      '';
    };
in
{
  pkgs,
  nixosConfig,
  installerBaseConfig ? nixosConfig,
  updateVersion,
}:
let
  inherit (pkgs) lib;
  inherit (lib) mkForce;

  hostUrl = "root@${nixosConfig.config.networking.hostName}";

  initialConfig = nixosConfig.extendModules {
    modules = [
      {
        image.repart.split = mkForce false;
        image.repart.compression = {
          enable = true;
          algorithm = "zstd";
        };
        system.image.version = mkForce "0-initial-image";
      }
    ];
  };

  initialImage = initialConfig.config.system.build.finalImage;
  initialToplevel = initialConfig.config.system.build.toplevel;

  updateConfig = nixosConfig.extendModules {
    modules = [
      {
        image.repart.split = mkForce true;
        image.repart.compression = {
          enable = true;
          algorithm = "zstd";
        };
        system.image.version = mkForce updateVersion;
        boot.uki.version = mkForce updateVersion;
      }
    ];
  };

  updateImage = updateConfig.config.system.build.finalImage;
  updateToplevel = updateConfig.config.system.build.toplevel;

  installerConfig =
    let
      baseName = initialConfig.config.image.baseName;
    in
    installerBaseConfig.extendModules {
      modules = [
        (
          { pkgs, lib, ... }:
          {
            partitions.isInstaller = true;

            system.image.id = lib.mkForce initialConfig.config.system.image.id;
            system.image.version = mkForce "installer";

            image.repart = {
              split = false;

              compression = {
                enable = true;
                algorithm = "zstd";
              };

              partitions."60-payload" = {
                repartConfig = {
                  Type = "linux-generic";
                  Label = "payload";
                  Format = "erofs";
                  Minimize = "best";
                };
                contents."/payload.zst".source = "${initialImage}/${baseName}.raw.zst";
              };
            };

            fileSystems."/mnt/payload" = {
              device = "/dev/disk/by-partlabel/payload";
              fsType = "erofs";
              options = [ "ro" ];
              neededForBoot = false;
            };

            environment.systemPackages = [
              (mkInstallScript {
                inherit pkgs;
                name = "mantle-install-payload";
                payload = "/mnt/payload/payload.zst";
              })
            ];
          }
        )
      ];
    };

  installerImage = installerConfig.config.system.build.finalImage;
  installerToplevel = installerConfig.config.system.build.toplevel;

  flashInitialImage =
    let
      baseName = initialConfig.config.image.baseName;
    in
    mkInstallScript {
      inherit pkgs;
      name = "flash-initial-image";
      payload = "${initialImage}/${baseName}.raw.zst";
    };

  flashInstallerImage =
    let
      baseName = installerConfig.config.image.baseName;
    in
    mkInstallScript {
      inherit pkgs;
      name = "flash-installer-image";
      payload = "${installerImage}/${baseName}.raw.zst";
    };

  updatePayload =
    let
      baseName = updateConfig.config.image.baseName;
      ukiDrv = updateConfig.config.system.build.uki;
      ukiFile = updateConfig.config.system.boot.loader.ukiFile;
    in
    pkgs.runCommand "update-${updateVersion}"
      {
        nativeBuildInputs = [ pkgs.zstd ];
      }
      ''
        mkdir -p $out
        cp \
          "${updateImage}/${baseName}.store.raw.zst" \
          "${updateImage}/${baseName}.store-verity.raw.zst" \
          $out
        zstd -1 "${ukiDrv}/${ukiFile}" -o "$out/${ukiFile}.zst"
      '';

  activateOverlay = pkgs.writeShellApplication {
    name = "activate-overlay";
    runtimeInputs = with pkgs; [
      openssh
    ];
    text = ''
      set -euo pipefail

      ssh "${hostUrl}" "activate-overlay";
    '';
  };

  deactivateOverlay = pkgs.writeShellApplication {
    name = "deactivate-overlay";
    runtimeInputs = with pkgs; [
      openssh
    ];
    text = ''
      set -euo pipefail

      ssh "${hostUrl}" "deactivate-overlay"
    '';
  };

  deployUpdate = pkgs.writeShellApplication {
    name = "deploy-update";
    runtimeInputs = with pkgs; [
      coreutils
      openssh
    ];
    text = ''
      set -euo pipefail

      scp -r "${updatePayload}" "${hostUrl}:/var/updates/"

      ssh "${hostUrl}" "systemd-sysupdate update --reboot"
    '';
  };

  deployOverlay = pkgs.writeShellApplication {
    name = "deploy-overlay";
    runtimeInputs = with pkgs; [
      nix
      openssh
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
      ';
    '';
  };

  cacheRoot =
    let
      toplevelDrvs = [
        installerToplevel
        initialToplevel
        updateToplevel
      ];

      imageDrvs = [
        installerImage
        initialImage
        updateImage
      ];

      depsOf = drv: (drv.buildInputs or [ ]) ++ (drv.nativeBuildInputs or [ ]);
      mkEntry = drv: {
        inherit (drv) name;
        path = drv;
      };
    in
    pkgs.linkFarm "mantle-cache-root" (
      (map mkEntry toplevelDrvs) ++ (map mkEntry (builtins.concatLists (map depsOf imageDrvs)))
    );
in
{
  inherit
    initialImage
    initialToplevel

    installerImage
    installerToplevel

    updatePayload
    updateToplevel

    flashInitialImage
    flashInstallerImage
    activateOverlay
    deactivateOverlay
    deployUpdate
    deployOverlay

    cacheRoot
    ;
}
