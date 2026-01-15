{ lib, config, ... }:
let
  cfg = config.mantle;
in
with lib;
{
  options = mkIf cfg {
    system.nixos-init.enable = true;

    # our image doesn't use nix
    # TODO optional garbage collection feature
    nix.enable = mkDefault false;

    system.switch.enable = mkForce cfg.storeOverlay.enable;

    boot.initrd.systemd.enable = mkDefault true;
    system.etc.overlay.enable = mkDefault true;
    systemd.sysusers.enable = true;

    system.tools.nixos-generate-config.enable = mkDefault false;
    boot.loader.grub.enable = mkDefault false;

    # minimize
    documentation = {
      enable = mkDefault false;
      doc.enable = mkDefault false;
      info.enable = mkDefault false;
      man.enable = mkDefault false;
      nixos.enable = mkDefault false;
    };

    environment = {
      defaultPackages = mkDefault [ ];
      stub-ld.enable = mkDefault false;
    };

    programs = {
      command-not-found.enable = mkDefault false;
      fish.generateCompletions = mkDefault false;
    };

    services = {
      logrotate.enable = mkDefault false;
      udisks2.enable = mkDefault false;
    };

    xdg = {
      autostart.enable = mkDefault false;
      icons.enable = mkDefault false;
      mime.enable = mkDefault false;
      sounds.enable = mkDefault false;
    };
  };
}
