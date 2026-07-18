{
  pkgs,
  nixosModule,
  modules,
  specialArgs ? { },
  nixosSystemArgs ? { },
}:
let
  inherit (pkgs) lib;

  baseConfig =
    # `nixpkgs.lib.nixosSystem` (the flake-level attr) is not available on
    # `pkgs.lib` (the raw lib re-exported inside `legacyPackages`), so call
    # `eval-config.nix` directly. This is exactly what `nixosSystem`
    # wraps (`lib = final; system = null; modules = ...`) and keeps
    # lib.init callable with a plain `pkgs` argument, as the example
    # flakes and the test suite do.
    import "${pkgs.path}/nixos/lib/eval-config.nix"
      (
        {
          lib = pkgs.lib;
          # Let `nixpkgs.hostPlatform`/`nixpkgs.system` be set modularly.
          system = null;
          modules = [ nixosModule ] ++ modules;
          inherit specialArgs;
        }
        // nixosSystemArgs
      );

  # The image version is sourced from the evaluated system configuration so
  # that callers drive it via `system.image.version` rather than a separate
  # argument. This keeps the version embedded in partition labels, the
  # update payload name, and os-release consistent with the booted image.
  version = baseConfig.config.system.image.version;

  # TODO utils taking in config _might_ require re-evaluating the module system
  utils = import "${pkgs.path}/nixos/lib/utils.nix" {
    inherit (pkgs) lib;
    inherit pkgs;
    config = baseConfig.config;
  };

  mkInstaller = import ./mk-installer.nix {
    inherit lib pkgs utils;
  };

  copyFromSplit = cfg: partition: {
    repartConfig = removeAttrs partition.repartConfig [ "Format" ] // {
      CopyBlocks = "${cfg.config.system.build.image}/${cfg.config.image.baseName}.${partition.repartConfig.SplitName}.raw";
    };
  };

  partitions = import ./mk-partitions.nix {
    inherit (baseConfig) config;
    inherit pkgs lib;
  };

  fullConfig = baseConfig.extendModules {
    modules = [
      {
        image.repart.partitions = lib.mkForce {
          "00-esp" = partitions.esp;
          "10-store-verity" = partitions.store-verity;
          "11-store" = partitions.store;
          "20-store-B-verity" = partitions.empty-store-verity;
          "21-store-B" = partitions.empty-store;
          "30-var" = partitions.var;
        };
      }
    ];
  };

  fullImage = fullConfig.config.system.build.image;

  # The update image carries only the store + store-verity partitions
  # that get shipped as the A/B update payload (the verity-store split
  # files). The ESP is kept too: the `image.repart.verityStore` final
  # image build injects the v2 UKI into the ESP and *requires* an ESP
  # partition to be present, so dropping it here makes the image build
  # fail. `updatePayload` below only ships store + store-verity + the
  # separate UKI, so the extra ESP split file is simply unused.
  updateConfig = baseConfig.extendModules {
    modules = [
      {
        image.repart.partitions = lib.mkForce {
          "00-esp" = partitions.esp;
          "10-store-verity" = partitions.store-verity;
          "11-store" = partitions.store;
        };
      }
    ];
  };

  updateImage = updateConfig.config.system.build.image;

  installerConfig = baseConfig.extendModules {
    modules = [
      {
        environment.systemPackages = [
          (mkInstaller "mantle-install" {
            "00-esp" = partitions.esp-installer-copy;
            "10-store-verity" = partitions.store-verity-copy;
            "11-store" = partitions.store-installer-copy;
          })
        ];

        image.repart = {
          name = "${baseConfig.config.system.image.id}-installer";
          partitions = lib.mkForce {
            "00-esp" = partitions.esp;
            "10-store-verity" = partitions.store-verity;
            "11-store" = partitions.store;
            "20-installer" = partitions.var-installer;
          };
        };
      }
    ];
  };

  installerImage = installerConfig.config.system.build.image;

  topLevel = baseConfig.config.system.build.toplevel;
  ukiDrv = updateConfig.config.system.build.uki;
  ukiFile = updateConfig.config.system.boot.loader.ukiFile;

  hostUrl = "root@${baseConfig.config.networking.hostName}";

  flash-to-device = mkInstaller "flash-to-device" {
    "00-esp" = copyFromSplit fullConfig partitions.esp;
    "10-store-verity" = copyFromSplit fullConfig partitions.store-verity;
    "11-store" = copyFromSplit fullConfig partitions.store;
    "20-store-B-verity" = partitions.empty-store-verity;
    "21-store-B" = partitions.empty-store;
    "30-var" = partitions.var;
  };

  flash-installer-to-device = mkInstaller "flash-installer-to-device" {
    "00-esp" = copyFromSplit installerConfig partitions.esp;
    "10-store-verity" = copyFromSplit installerConfig partitions.store-verity;
    "11-store" = copyFromSplit installerConfig partitions.store;
  };

  updatePayload =
    let
      updateBase = updateConfig.config.image.baseName;
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
        copy --to "ssh://${hostUrl}:/var/nix/upper" "${topLevel}"
      ssh "${hostUrl}" '
        set -euo pipefail
        activate-overlay
        ${topLevel}/bin/switch-to-configuration test
      '
    '';
  };

in
{
  inherit
    fullImage
    installerImage
    updateImage

    updatePayload
    topLevel

    flash-to-device
    flash-installer-to-device

    activate-overlay
    deactivate-overlay
    clear-overlay
    deploy-update
    deploy-overlay
    ;
}
