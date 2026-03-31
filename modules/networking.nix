{ pkgs, ... }:
let
  activate-overlay = pkgs.writeShellScriptBin "mount-overlay" ''
    set -euo pipefail

    mkdir -p /var/nix/upper /var/nix/work

    if [ "$(findmnt -n -o FSTYPE /nix/store || true)" = overlay ]; then
      exit 0
    fi

    mount -t overlay overlay \
      -o lowerdir=/nix/lower,upperdir=/var/nix/upper,workdir=/var/nix/work \
      /nix/store
  '';

  deactivate-overlay = pkgs.writeShellScriptBin "deactivate-overlay" ''
    set -euo pipefail

    if [ "$(findmnt -n -o FSTYPE /nix/store || true)" = overlay ]; then
      umount /nix/store
    fi
  '';
in
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

  environment.systemPackages = [
    activate-overlay
    deactivate-overlay
  ];
}
