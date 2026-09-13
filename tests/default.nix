{
  pkgs,
  mantle ? import ../.,
}:
{
  image-update = pkgs.testers.runNixOSTest (import ./image-update.nix { inherit pkgs mantle; });
  installer = pkgs.testers.runNixOSTest (import ./installer.nix { inherit pkgs mantle; });
  overlay = pkgs.testers.runNixOSTest (import ./overlay.nix { inherit pkgs mantle; });
}
