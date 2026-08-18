{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    mantle = {
      url = "path:/home/asa/Projects/mantle";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware = {
      url = "github:nixos/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      mantle,
      nixos-hardware,
    }:
    let
      allSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs allSystems;
      pkgsFor = forAllSystems (system: nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        system:
        mantle.lib.init pkgsFor.${system} {
          modules = [
            nixos-hardware.nixosModules.raspberry-pi-4
            {
              nixpkgs = {
                buildPlatform = system;
                hostPlatform = "aarch64-linux";
              };

              mantle = {
                enable = true;
                overlay.enable = true;
                partitions = {
                  esp.size = "128M";
                  store.size = "5G";
                  store-verity.size = "275M";
                  var.size = "5G";
                };
              };

              system.image.id = "mantle-pi";
              system.image.version = "${toString self.lastModified}-${self.shortRev or "dev"}";

              networking.hostName = "mantle-pi";
            }
          ];
        }
      );

      apps = forAllSystems (
        system:
        let
          mkApp = drv: {
            type = "app";
            program = nixpkgs.lib.getExe drv;
          };
        in
        {
          flash-to-device = mkApp self.packages.${system}.flash-to-device;
          flash-installer-to-device = mkApp self.packages.${system}.flash-installer-to-device;
          activate-overlay = mkApp self.packages.${system}.activate-overlay;
          deactivate-overlay = mkApp self.packages.${system}.deactivate-overlay;
          clear-overlay = mkApp self.packages.${system}.clear-overlay;
          deploy-update = mkApp self.packages.${system}.deploy-update;
          deploy-overlay = mkApp self.packages.${system}.deploy-overlay;
        }
      );
    };
}
