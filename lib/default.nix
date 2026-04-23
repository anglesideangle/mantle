let
  mkInstallScript =
    { pkgs, payload }:
    pkgs.writeShellApplication {
      name = "mantle-install";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.util-linux
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

        dd if="${payload}" of="$device" bs=64M conv=fsync status=progress
      '';
    };
in
{
  pkgs,
  nixosConfig,
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
          enable = mkForce false;
          algorithm = "zstd";
        };
        system.image.version = mkForce "0-first-install";
      }
    ];
  };

  updateConfig = nixosConfig.extendModules {
    modules = [
      {
        image.repart.split = mkForce true;
        image.repart.compression.enable = mkForce true;
        system.image.version = mkForce updateVersion;
        boot.uki.version = mkForce updateVersion;
      }
    ];
  };

  initialImage = initialConfig.config.system.build.finalImage;

  installerConfig =
    let
      baseName = initialConfig.config.image.baseName;
    in
    initialConfig.extendModules {
      modules = [
        (
          { pkgs, lib, ... }:
          {
            system.image.id = lib.mkForce "${initialConfig.config.system.image.id}-installer";
            partitions.isInstaller = true;

            environment.systemPackages = [
              (mkInstallScript {
                inherit pkgs;
                payload = "${initialImage}/${baseName}.raw";
              })
            ];
          }
        )
      ];
    };

  installerImage = installerConfig.config.system.build.finalImage;

  flashInitialImage =
    let
      baseName = initialConfig.config.image.baseName;
    in
    mkInstallScript {
      inherit pkgs;
      payload = "${initialImage}/${baseName}.raw";
    };

  flashInstallerImage =
    let
      baseName = installerConfig.config.image.baseName;
    in
    mkInstallScript {
      inherit pkgs;
      payload = "${installerImage}/${baseName}.raw";
    };

  updatePayload =
    let
      baseName = updateConfig.config.image.baseName;
      updateDrv = updateConfig.config.system.build.finalImage;
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
          "${updateDrv}/${baseName}.store.raw.zst" \
          "${updateDrv}/${baseName}.store-verity.raw.zst" \
          $out
        zstd -1 "${ukiDrv}/${ukiFile}" -o "$out/${ukiFile}.zst"
      '';

  overlayToplevel = updateConfig.config.system.build.toplevel;

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
        copy --to "ssh://${hostUrl}:/var/nix/upper" "${overlayToplevel}"

      ssh "${hostUrl}" '
        set -euo pipefail
        activate-overlay
        ${overlayToplevel}/bin/switch-to-configuration test
      ';
    '';
  };
in
{
  inherit

    initialImage
    installerImage
    updatePayload
    overlayToplevel

    flashInitialImage
    flashInstallerImage
    activateOverlay
    deactivateOverlay
    deployUpdate
    deployOverlay
    ;
}
