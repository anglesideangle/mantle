{
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.partitions;
in
{
  config = mkIf cfg.enable {
    system.nixos-init.enable = true;

    boot.initrd.systemd.enable = true;
    system.etc.overlay.enable = true;
    system.etc.overlay.mutable = false;
    systemd.sysusers.enable = false;
    services.userborn.enable = true;
    services.userborn.static = true;
    boot.tmp.useTmpfs = true;

    system.tools.nixos-generate-config.enable = false;
    boot.loader.grub.enable = false;

    security.sudo.enable = false;

    nix.enable = false;

    system.switch.enable = mkDefault false;

    boot.supportedFilesystems = mkDefault [
      "erofs"
      "ext4"
    ];

    fileSystems = {
      "/" = mkDefault {
        fsType = "tmpfs";
        options = [ "mode=755" ];
      };

      "/var" = mkDefault {
        device = "/dev/disk/by-partlabel/${cfg.var.label}";
        fsType = cfg.var.format;
        neededForBoot = true;
        options = [
          "noatime"
          "data=journal"
        ];
      };

      "/boot" = mkDefault {
        device = "/dev/disk/by-partlabel/${cfg.esp.label}";
        fsType = cfg.esp.format;
      };

      "/nix/store" = mkDefault {
        device = "/usr/nix/store";
        fsType = "none";
        neededForBoot = true;
        options = [
          "bind"
          "ro"
        ];
      };
    };
  };
}
