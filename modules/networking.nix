{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = lib.mkIf config.mantle.overlay.enable {
    environment.systemPackages = [ pkgs.rsync ];

    systemd.tmpfiles.rules = [
      "f /var/nix/prev-os-release 0755 root root -"
    ];

    systemd.services.check-clear-store-upper = {
      description = "Clear /var/nix/upper if the base image has changed.";

      requires = [ "var.mount" ];
      after = [ "var.mount" ];

      serviceConfig = {
        Type = "oneshot";
        ExecCondition = ''
          ${pkgs.bash}/bin/sh -c "! ${pkgs.diffutils}/bin/cmp -s /var/nix/prev-os-release /run/booted-system/etc/os-release"
        '';
        ExecStart = "${pkgs.bash}/bin/sh -c '${pkgs.coreutils}/bin/rm -rf /var/nix/*'";
        ExecStartPost = "${pkgs.coreutils}/bin/cp /run/booted-system/etc/os-release /var/nix/prev-os-release";
      };
    };

    systemd.services.nix-store-overlay = {
      description = "Mount a writeable overlay to /nix/store.";

      requires = [ "var.mount" ];
      after = [
        "var.mount"
        "check-clear-store-upper.service"
      ];

      # A restart of this service would pull the overlay out from under a running
      # system configuration
      restartIfChanged = false;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/nix/upper/nix/store /var/nix/work";
        ExecStart = ''
          ${pkgs.mount}/bin/mount \
            -t overlay overlay \
            -o lowerdir=/usr/nix/store,upperdir=/var/nix/upper/nix/store,workdir=/var/nix/work \
            /nix/store
        '';
        ExecStop = "${pkgs.umount}/bin/umount -l /nix/store";
      };
    };
  };
}
