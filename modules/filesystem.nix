{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.mantle;
in
with lib;
{
  # boot.uki.name = imageCfg.name;
  # boot.uki.name = "amos";
  # system.image.id = "amos";
  # system.image.version = "";

  # system.nixos.distroId = "amos";
  # system.nixos.distroName = "AmOS";

  imports = [ ./repart.nix ];

  config = mkIf cfg.image.enable {

    boot.uki.tries = mkDefault 2;

    # Mount `/var` `/boot` and `/nix/store` according to repart config
    # `/` is a tmpfs, meaning any writes to directories will be forgotten on boot
    # `/var` is writeable to allow for logging
    fileSystems = {
      "/" =
        let
          partConf = config.image.repart.partitions."store".repartConfig;
        in
        {
          device = "/dev/disk/by-partlabel/${partConf.Label}";
          fsType = partConf.Format;
          neededForBoot = true;
        };

      "/var" =
        let
          partConf = config.image.repart.partitions."var".repartConfig;
        in
        {
          device = "/dev/disk/by-partlabel/${partConf.Label}";
          fsType = partConf.Format;
          neededForBoot = true;
          options = [
            "default"
            "noatime"
            "data=journal"
          ];
        };

      "/boot" =
        let
          partConf = config.image.repart.partitions."esp".repartConfig;
        in
        {
          device = "/dev/disk/by-partlabel/${partConf.Label}";
          fsType = partConf.Format;
        };

      # see ./repart.nix:
      # if storeOverlay is enabled, immutable store is /nix/.ro-store
      # and /nix/store is an overlayfs with /var/nix/upper > /nix/.ro-store
      # otherwise, immutable store is /nix/store and overlayfs is not needed
      "/nix/store" = mkIf cfg.storeOverlay.enable {
        device = "overlay";
        fsType = "overlay";
        neededForBoot = true;
        options = [
          "lowerdir=/nix/.ro-store"
          "upperdir=/var/nix/upper"
          "workdir=/var/nix/work"
        ];
        depends = [
          "/nix/.ro-store"
          "/var"
        ];
      };
    };

    # TODO move?
    boot.tmp.useTmpfs = mkForce true;

    # Ensure overlay directories exist on boot
    systemd.tmpfiles.rules = [
      "d /var/nix/upper 0755 root root -"
      "d /var/nix/work 0755 root root -"
    ];

    # needed for sanitize-overlay initrd script
    boot.initrd.systemd.packages = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.e2fsprogs
    ];

    # The service has two tasks:
    #
    # 1) Ensure that, under no circumstances, the overlayfs realizations will
    #    mask the immutable underlay store's realizations
    #    This could otherwise be problematic because the underlay is a config that
    #    is validated to work and realizations aren't necessarily bit-for-bit
    #    reproducible (nix is input addressed).
    #
    # 2) Ensure that on new system generations (eg. previously logged generation)
    #    does not match the current one, that the overlayfs is wiped. This is
    #    because the overlay nix store relies on the immutable underlay, so
    #    replacing the base without wiping the overlay would lead to dangling
    #    paths and a broken store.
    #    It is better to do this in initrd than on deploy-image because deploying
    #    the image and then wiping the overlay store would not be atomic, and
    #    would be prone to failure in adverse conditions.
    boot.initrd.systemd.services.sanitize-overlay = lib.mkIf cfg.storeOverlay.enable {

      # 1. Wait for the underlying partitions to be mounted at /sysroot/...
      #    (Systemd automatically generates these mount units from image.nix)
      # 2. Run before the overlay tries to mount at /sysroot/nix/store
      after = [
        "sysroot.mount"
        "sysroot-var.mount"
      ];
      requires = [
        "sysroot.mount"
        "sysroot-var.mount"
      ];
      before = [ "sysroot-nix-store.mount" ];

      unitConfig.DefaultDependencies = false;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        BASE_DIR="/sysroot/nix/.ro-store"
        VAR_DIR="/sysroot/var"
        VERSION_FILE="$VAR_DIR/.image_version"
        CURRENT_VERSION="${config.system.image.version}"

        # make version file mutable to update the version and check for
        # previously logged system image version
        if [ -f "$VERSION_FILE" ]; then
          chattr -i "$VERSION_FILE" || true
          PREV_VERSION=$(cat "$VERSION_FILE")
        else
          PREV_VERSION="unknown"
        fi

        if [ "$CURRENT_VERSION" != "$PREV_VERSION" ]; then
          echo "System image version changed since last boot ($CURRENT_VERSION != $PREV_VERSION), wiping overlay store..."

          if [ -d "$VAR_DIR/nix/upper" ]; then
            find "$VAR_DIR/nix/upper" -mindepth 1 -delete || true
          fi
          if [ -d "$VAR_DIR/nix/work" ]; then
            find "$VAR_DIR/nix/work" -mindepth 1 -delete || true
          fi

          echo "$CURRENT_VERSION" > "$VERSION_FILE"
        else
          echo "System image version matches previous boot, not clearing overlay store."
        fi

        # re-lock version file as immutable
        chattr +i "$VERSION_FILE"

        BASE_STORE="$BASE_DIR/nix/store"
        OVERLAY_STORE="$VAR_DIR/nix/upper/nix/store"

        # sanitize overlay by removing all paths that would clobber the base fs
        if [ -d "$OVERLAY_STORE" ]; then
          echo "Sanitizing overlay store to prevent overriding base immutable store realisations..."
          for path in "$OVERLAY_STORE"/*; do
            # if file exists in base and overlay, delete from overlay
            [ -e "$path" ] || continue
            filename=$(basename "$path")
            if [ -e "$BASE_STORE/$filename" ]; then
               rm -rf "$path"
            fi
          done
        fi

        # remove whiteouts (restore visibility of base files)
        find "$OVERLAY_STORE" -type c -delete 2>/dev/null || true
      '';
    };
  };

}
