{
  pkgs,
  nixosConfig,
  updateVersion,
}:
let
  inherit (pkgs) lib;
  inherit (lib) mkForce;

  hostUrl = "root@${nixosConfig.config.networking.hostName}";

  flashConfig = nixosConfig.extendModules {
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

  flashImage = flashConfig.config.system.build.image;

  updatePayload =
    let
      baseName = updateConfig.config.image.baseName;
      updateDrv = updateConfig.config.system.build.image;
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

  flashInstallImage =
    let
      baseName = flashConfig.config.image.baseName;
      imageFile = "${flashImage}/${baseName}.raw";
    in
    pkgs.writeShellApplication {
      name = "flash";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.nix
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

        echo "About to flash ${imageFile} to $device."
        printf "This will destroy all data on %s. Continue? [y/N] " "$device"
        read -r answer

        case "$answer" in
          y|Y|yes|YES)
            ;;
          *)
            echo "Aborted"
            exit 1
            ;;
        esac

        dd if="${imageFile}" of="$device" bs=16M conv=fsync status=progress
      '';
    };

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
    flashImage
    updatePayload
    overlayToplevel

    flashInstallImage
    activateOverlay
    deactivateOverlay
    deployUpdate
    deployOverlay
    ;
}
