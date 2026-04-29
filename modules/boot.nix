{ lib, config, ... }:
with lib;
let
  cfg = config.partitions;
  # store-label = "${cfg.store.label-prefix}_${config.system.image.version}";
in
{
  config = mkIf cfg.enable {
    system.nixos-init.enable = true;

    boot.initrd.systemd.enable = true;
    system.etc.overlay.enable = true;
    system.etc.overlay.mutable = true; # TODO upstream fix
    systemd.sysusers.enable = false;
    services.userborn.enable = true;
    # services.userborn.static = true; # TODO nixos 26.05
    boot.tmp.useTmpfs = true;

    system.tools.nixos-generate-config.enable = false;
    boot.loader.grub.enable = false;

    # security.wrappers = mkForce { };
    security.sudo.enable = false;

    nix.enable = false;

    system.switch.enable = mkDefault false; # TODO true for overlay

    # boot.initrd.systemd.storePaths = mkForce [ ];

    fileSystems = {
      "/" = {
        fsType = "tmpfs";
      };

      "/var" = mkIf (!cfg.isInstaller) {
        device = "/dev/disk/by-partlabel/${cfg.var.label}";
        fsType = cfg.var.format;
        neededForBoot = true;
        options = [
          "noatime"
          "data=journal"
        ];
      };

      "/boot" = {
        device = "/dev/disk/by-partlabel/${cfg.esp.label}";
        fsType = cfg.esp.format;
      };

      # "/nix/lower" = {
      # device = "/dev/disk/by-partlabel/${store-label}";
      # device = "/usr/nix/store";
      #   fsType = cfg.store.format;
      #   neededForBoot = true;
      # };

      "/nix/store" = {
        device = "/usr/nix/store";
        fsType = "none";
        neededForBoot = true;
        options = [
          "bind"
          "ro"
        ];
        # depends = [ "/nix/lower" ];
      };
    };
  };
}
