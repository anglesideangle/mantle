{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.partitions;

  inherit (lib)
    mkDefault
    mkForce
    mkIf
    ;
in
{
  config = mkIf cfg.enable {
    system.image.id = config.system.name;
    system.image.version = config.system.version;

    boot.uki.name = config.system.name;
    boot.uki.version = config.system.version;

    system.nixos-init.enable = true;
    boot.initrd.systemd.enable = true;

    system.etc.overlay.enable = true;
    system.etc.overlay.mutable = false;

    systemd.sysusers.enable = false;
    services.userborn.enable = true;
    services.userborn.static = mkDefault true;
    system.switch.enable = mkDefault false;

    boot.tmp.useTmpfs = true;

    # can't create /usr/bin/env on immutable /usr
    environment.usrbinenv = mkForce null;

    nix.enable = false;
    system.disableInstallerTools = true;

    security.account-utils.enable = true;
    security.enableWrappers = false;
    security.sudo.enable = false;

    networking.useNetworkd = mkDefault true;

    boot.supportedFilesystems = mkDefault [
      "erofs"
      "ext4"
    ];

    fileSystems = {
      "/" = {
        fsType = "tmpfs";
        options = [
          "mode=755"
          "nosuid"
        ];
      };

      "/var" = {
        device = "/dev/disk/by-partlabel/${cfg.var.label}";
        fsType = cfg.var.format;
        neededForBoot = true;
        options = [
          "noatime"
          "nosuid"
          "nodev"
          "noexec"
        ];
      };

      "/boot" = {
        device = "/dev/disk/by-partlabel/${cfg.esp.label}";
        fsType = cfg.esp.format;
        options = [
          "nosuid"
          "nodev"
          "noexec"
        ];
      };

      "/nix/store" = {
        device = "/usr/nix/store";
        fsType = "none";
        neededForBoot = true;
        options = [
          "bind"
          "ro"
          "nosuid"
          "nodev"
          "umask=077"
        ];
      };
    };

    # Ensure the /nix/store bind mount is unmounted before
    # systemd-veritysetup@usr.service stops during shutdown, otherwise the
    # verity device is still in use and deactivation fails.
    systemd.services."systemd-veritysetup@usr" = {
      serviceConfig.ExecStopPre = "${pkgs.util-linux}/bin/umount /nix/store || true";
    };
  };
}
