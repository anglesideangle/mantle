{ pkgs, ... }:
{
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/nix/upper/nix/store 0755 root root -"
    "d /var/nix/work 0755 root root -"
  ];

  systemd.services.check-clear-store-upper = {
    description = "Clear /var/nix/upper if the base image has changed.";

    requires = [
      "var.mount"
      "systemd-tmpfiles-setup.service"
    ];
    after = [
      "var.mount"
      "systemd-tmpfiles-setup.service"
    ];

    serviceConfig = {
      Type = "oneshot";
      ExecCondition = ''
        ${pkgs.bash}/bin/sh -c "! ${pkgs.diffutils}/bin/cmp -s /var/nix/prev-os-release /etc/os-release"
      '';
      ExecStart = "${pkgs.bash}/bin/sh -c '${pkgs.coreutils}/bin/rm -rf /var/nix/*'";
      ExecStartPost = "${pkgs.coreutils}/bin/cp /etc/os-release /var/nix/prev-os-release";
    };
  };

  systemd.services.nix-store-overlay = {
    description = "Mount a writeable overlay to /nix/store.";

    requires = [
      "var.mount"
      "systemd-tmpfiles-setup.service"
    ];
    after = [
      "var.mount"
      "systemd-tmpfiles-setup.service"
      "check-clear-store-upper.service"
    ];

    # A restart would drop the overlay out from under a running
    # switched-to configuration; switch-to-configuration must leave this
    # unit alone across generations.
    restartIfChanged = false;

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${pkgs.mount}/bin/mount \
          -t overlay overlay \
          -o lowerdir=/usr/nix/store,upperdir=/var/nix/upper/nix/store,workdir=/var/nix/work \
          /nix/store
      '';
      ExecStop = "${pkgs.umount}/bin/umount -l /nix/store";
    };
  };
}
