{ lib, config, ... }:
with lib;
let
  cfg = config.partitions;
  store-label = "${cfg.store.label-prefix}_${config.system.image.version}";
in
{
  config = mkIf cfg.enable {
    system.nixos-init.enable = true;

    boot.initrd.systemd.enable = true;
    system.etc.overlay.enable = true;
    system.etc.overlay.mutable = false; # TODO might break
    systemd.sysusers.enable = true;
    boot.tmp.useTmpfs = true;

    system.tools.nixos-generate-config.enable = false;
    boot.loader.grub.enable = false;

    security.wrappers = mkForce { };
    security.sudo.enable = false;

    nix.enable = false;

    system.switch.enable = mkDefault false; # TODO true for overlay

    fileSystems = {
      "/" = {
        fsType = "tmpfs";
      };

      "/var" = {
        device = "/dev/disk/by-partlabel/${cfg.var.label}";
        fsType = cfg.var.format;
        neededForBoot = true;
        options = [
          "default"
          "noatime"
          "data=journal"
        ];
      };

      "/boot" = {
        device = "/dev/disk/by-partlabel/${cfg.esp.label}";
        fsType = cfg.esp.format;
      };

      "/nix/lower" = {
        device = "/dev/disk/by-partlabel/${store-label}";
        fsType = cfg.store.format;
        neededForBoot = true;
      };

      "/nix/store" = {
        device = "/nix/lower";
        fsType = "none";
        neededForBoot = true;
        options = [
          "bind"
          "ro"
        ];
        depends = [ "/nix/lower" ];
      };
    };
  };
}
