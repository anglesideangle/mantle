{ pkgs, self }:
{
  image-update = pkgs.testers.runNixOSTest (
    import ./image-update.nix {
      inherit pkgs self;
    }
  );
  installer = pkgs.testers.runNixOSTest (
    import ./installer.nix {
      inherit pkgs self;
    }
  );
  overlay = pkgs.testers.runNixOSTest (
    import ./overlay.nix {
      inherit pkgs self;
    }
  );
}
