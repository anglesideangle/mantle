pkgs: args:
let
  inherit (pkgs) lib;

  # Creates a new repart definition containing instructions for systemd-repart
  # to copy from the path of the specified original `partition` in the nix
  # store.
  copyFromRepartOutput =
    config: partition:
    let
      uuid-file = pkgs.runCommand "get-uuid" { } ''
        ${pkgs.jq}/bin/jq -r \
          '.[] | select(.label == "${partition.repartConfig.Label}") | .uuid' \
          "${config.system.build.image}/repart-output.json" \
          > $out
      '';
      uuid = lib.concatStringsSep "" (lib.splitString "-" (lib.trim (builtins.readFile uuid-file)));
      # Expand %U in SplitName so CopyBlocks references the correct artifact by
      # name (e.g. "store_<uuid>.raw" instead of "store_%U.raw").
      splitName = builtins.replaceStrings [ "%U" ] [ uuid ] partition.repartConfig.SplitName;
    in
    {
      repartConfig =
        removeAttrs partition.repartConfig [
          "Format"
          "Verity"
          "VerityMatchKey"
        ]
        // {
          CopyBlocks = "${config.system.build.image}/${config.image.baseName}.${splitName}.raw";
          UUID = uuid;
        };
    };

  # Creates a new repart definition containing instructions for systemd-repart
  # to copy from the path of the specified original `partition` on the disk.
  copyFromPartition = partition: {
    repartConfig =
      removeAttrs partition.repartConfig [
        "Format"
        "Verity"
        "VerityMatchKey"
      ]
      // {
        CopyBlocks = "auto";
      };
  };

  baseConfig = import "${pkgs.path}/nixos/lib/eval-config.nix" (
    {
      system = null;
      modules = (args.modules or [ ]) ++ [ ./modules/default.nix ];
    }
    // removeAttrs args [ "modules" ]
  );

  fullConfig = baseConfig.extendModules {
    modules = [
      (
        { config, ... }:
        let
          defs = config.system.build._partitionDefs;
        in
        {
          image.repart.partitions = {
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
      {
        image.repart.compression = {
          enable = true;
          algorithm = "zstd";
        };
      }
    ];
  };

  overlayConfig = baseConfig.extendModules {
    modules = [
      ({ lib, config, ... }: {
        system.image.version = lib.mkForce "${config.mantle.version}~overlay";
        assertions = [
          {
            assertion = config.mantle.overlay.enable;
            message = "the overlay extension cannot be used when the mantle overlay is not enabled.";
          }
        ];
      })
    ];
  };

  installerConfig = baseConfig.extendModules {
    modules = [
      (
        { config, lib, ... }:
        let
          defs = config.system.build._partitionDefs;
          mkInstaller = config.system.build._mkInstallerHostPlatform;
        in
        {
          fileSystems."/var" = {
            device = lib.mkForce "none";
            fsType = lib.mkForce "tmpfs";
          };

          environment.systemPackages = [
            (mkInstaller "mantle-install" {
              "00-esp" = copyFromPartition defs.esp;
              "10-store-verity" = copyFromPartition defs.store-verity;
              "11-store" = copyFromPartition defs.store;
              "20-store-B-verity" = defs.empty-store-verity;
              "21-store-B" = defs.empty-store;
              "30-var" = defs.var;
            })
          ];

          image.repart.name = "${config.system.image.id}-installer";
        }
      )
    ];
  };

  flash-to-device =
    let
      cfg = baseConfig.extendModules {
        modules = [
          (
            { config, ... }:
            let
              defs = config.system.build._partitionDefs;
              mkInstaller = config.system.build._mkInstallerBuildPlatform;
            in
            {
              system.build._flash-to-device = mkInstaller "flash-to-device" {
                "00-esp" = copyFromRepartOutput config defs.esp;
                "10-store-verity" = copyFromRepartOutput config defs.store-verity;
                "11-store" = copyFromRepartOutput config defs.store;
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
            { config, ... }:
            let
              defs = config.system.build._partitionDefs;
              mkInstaller = config.system.build._mkInstallerBuildPlatform;
            in
            {
              system.build._flash-installer-to-device = mkInstaller "flash-to-device" {
                "00-esp" = copyFromRepartOutput config defs.esp;
                "10-store-verity" = copyFromRepartOutput config defs.store-verity;
                "11-store" = copyFromRepartOutput config defs.store;
              };
            }
          )
        ];
      };
    in
    cfg.config.system.build._flash-installer-to-device;

  updatePayload =
    let
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
          "${updatePartitions}"/*.store_*.raw.zst \
          "${updatePartitions}"/*.store-verity_*.raw.zst \
          $out
        zstd -1 "${ukiDrv}/${ukiFile}" -o "$out/${ukiFile}.zst"
      '';

  getSshUrl = "\${1:-\${DEVICE_URL:?Error: ssh url was not provided as an argument and DEVICE_URL was unset.}}";

  getSshOpts = ''
    sshOpts=()
    sshKey="''${2:-''${SSH_KEY:-}}"
    if [ -n "$sshKey" ]; then sshOpts+=(-i "$sshKey"); fi
  '';

  activate-overlay = pkgs.writeShellApplication {
    name = "activate-overlay";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      ${getSshOpts}
      ssh "''${sshOpts[@]}" "${getSshUrl}" "systemctl start nix-store-overlay"
    '';
  };

  deactivate-overlay = pkgs.writeShellApplication {
    name = "deactivate-overlay";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      ${getSshOpts}
      ssh "''${sshOpts[@]}" "${getSshUrl}" "systemctl stop nix-store-overlay"
    '';
  };

  clear-overlay = pkgs.writeShellApplication {
    name = "clear-overlay";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      ${getSshOpts}
      ssh "''${sshOpts[@]}" "${getSshUrl}" "rm -rf /var/nix/upper"
    '';
  };

  deploy-update = pkgs.writeShellApplication {
    name = "deploy-update";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.openssh
    ];
    text = ''
      ${getSshOpts}
      scp -r "''${sshOpts[@]}" "${updatePayload}" "${getSshUrl}:/var/updates/"
      ssh "''${sshOpts[@]}" "${getSshUrl}" "systemd-sysupdate update --reboot"
    '';
  };

  # Activates the overlay and deploys the `updateToplevel` closure using rsync.
  deploy-overlay = pkgs.writeShellApplication {
    name = "deploy-overlay";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nix
      pkgs.openssh
      pkgs.rsync
    ];
    text = ''
      hostUrl=${getSshUrl};
      ${getSshOpts}

      ssh "''${sshOpts[@]}" "''${hostUrl}" "systemctl start nix-store-overlay"

      nix --extra-experimental-features "nix-command flakes" \
        path-info -r "${overlayToplevel}" \
      | rsync \
        --archive \
        --recursive \
        --info=progress2 \
        --compress \
        --compress-choice=zstd \
        --files-from=- \
        --relative \
        --ignore-existing \
        -e "ssh ''${sshOpts[*]:-}" \
        / "''${hostUrl}:/"

      ssh "''${sshOpts[@]}" "''${hostUrl}" "
        systemd-run --no-block --remain-after-exit \
          --unit=deploy-overlay-switch \
          ${overlayToplevel}/bin/switch-to-configuration test
      "

      timeout=300
      elapsed=0
      while true; do
        state=$(ssh -o ConnectTimeout=5 "''${sshOpts[@]}" "''${hostUrl}" \
          'systemctl is-active deploy-overlay-switch.service' || true)
        case "$state" in
          active) break ;;
          failed)
            echo "deploy-overlay: switch failed" >&2
            ssh "''${sshOpts[@]}" "''${hostUrl}" \
              'journalctl -u deploy-overlay-switch.service --no-pager -o cat' >&2
            exit 1
            ;;
          *) ;;
        esac
        if [ "$elapsed" -ge "$timeout" ]; then
          echo "deploy-overlay: switch timed out after ''${timeout}s (last state: ''${state:-unknown})" >&2
          ssh "''${sshOpts[@]}" "''${hostUrl}" \
            'journalctl -u deploy-overlay-switch.service --no-pager -o cat --since "-1min ago"' >&2
          exit 1
        fi
        sleep 2
        elapsed=$((elapsed + 2))
      done
    '';
  };

  fullPartitions = fullConfig.config.system.build.image;
  updatePartitions = updateConfig.config.system.build.image;
  installerPartitions = installerConfig.config.system.build.image;

  fullImage = "${fullPartitions}/${fullConfig.config.image.filePath}";
  installerImage = "${installerPartitions}/${fullConfig.config.image.filePath}";

  fullToplevel = fullConfig.config.system.build.toplevel;
  updateToplevel = updateConfig.config.system.build.toplevel;
  installerToplevel = installerConfig.config.system.build.toplevel;
  overlayToplevel = overlayConfig.config.system.build.toplevel;
  ukiDrv = updateConfig.config.system.build.uki;
in
{
  inherit
    fullPartitions
    installerPartitions
    updatePartitions

    fullImage
    installerImage
    updatePayload

    fullToplevel
    installerToplevel
    updateToplevel
    overlayToplevel

    flash-to-device
    flash-installer-to-device
    activate-overlay
    deactivate-overlay
    clear-overlay
    deploy-update
    deploy-overlay
    ;
}
