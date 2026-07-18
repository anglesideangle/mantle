{ pkgs, ... }:
let
  # `findmnt -n -o FSTYPE <path>` returns *every* mount in the stack at the
  # given path, oldest first (underlying dm-verity /usr erofs, the read-only
  # /nix/store bind, then any overlay on top). Taking the last line gives the
  # topmost filesystem, which is what we want to inspect here.
  topmost-fstype = "findmnt -n -o FSTYPE -T /nix/store | tail -n1";

  activate-overlay = pkgs.writeShellScriptBin "mount-overlay" ''
    set -euo pipefail

    mkdir -p /var/nix/upper /var/nix/work

    if [ "$(${topmost-fstype} || true)" = overlay ]; then
      exit 0
    fi

    mount -t overlay overlay \
      -o lowerdir=/usr/nix/store,upperdir=/var/nix/upper,workdir=/var/nix/work \
      /nix/store
  '';

  deactivate-overlay = pkgs.writeShellScriptBin "deactivate-overlay" ''
    set -euo pipefail

    if [ "$(${topmost-fstype} || true)" = overlay ]; then
      # /nix/store is busy on a running system (open libs, store paths in
      # use), so a plain `umount` returns EBUSY. A lazy umount detaches
      # the overlay from the namespace immediately; already-open files
      # keep the overlay alive until they're closed, while new lookups go
      # back to the read-only verity bind mount underneath.
      umount -l /nix/store
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
