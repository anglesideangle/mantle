{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.mantle;

  inherit (lib)
    mkDefault
    mkForce
    mkIf
    ;
in
{
  config = mkIf cfg.enable {
    system.nixos-init.enable = true;
    boot.initrd.systemd.enable = true;

    system.etc.overlay.enable = true;
    system.etc.overlay.mutable = false;

    systemd.sysusers.enable = false;
    services.userborn.enable = true;

    services.userborn.static = !cfg.overlay.enable;
    system.switch.enable = cfg.overlay.enable;

    boot.tmp.useTmpfs = true;

    # can't create /usr/bin/env on immutable /usr
    environment.usrbinenv = mkForce null;

    nix.enable = false;
    system.disableInstallerTools = true;

    security.account-utils.enable = true;
    security.enableWrappers = false;
    security.sudo.enable = false;

    boot.kernelParams = [ "systemd.machine_id=firmware" ];

    networking.useNetworkd = mkDefault true;

    boot.supportedFilesystems = mkDefault [
      "erofs"
      "ext4"
    ];

    fileSystems =
      let
        inherit (cfg) partitions;
      in
      {
        "/" = {
          fsType = "tmpfs";
          options = [
            "mode=755"
            "nosuid"
          ];
        };

        "/var" = {
          device = "/dev/disk/by-partlabel/${partitions.var.label}";
          fsType = partitions.var.format;
          neededForBoot = true;
          options = [
            "noatime"
            "nosuid"
            "nodev"
            "noexec"
          ];
        };

        "/boot" = {
          device = "/dev/disk/by-partlabel/${partitions.esp.label}";
          fsType = partitions.esp.format;
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
