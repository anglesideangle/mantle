{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    mantle = {
      url = "path:/home/asa/Projects/mantle";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:nixos/nixos-hardware";
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

      pi4SystemCross = forAllSystems (
        buildPlatform:
        nixpkgs.lib.nixosSystem {
          modules = [
            mantle.nixosModules.default
            nixos-hardware.nixosModules.raspberry-pi-4
            {
              nixpkgs = {
                inherit buildPlatform;
                hostPlatform = "aarch64-linux";
                # hostPlatform = "x86_64-linux";
              };

              partitions = {
                enable = true;
                esp.size = "128M";
                store.size = "5G";
                var.size = "5G";
              };

              system.image.id = "imageid";
              boot.uki.name = "ukiname";
              networking.hostName = "mantle-target";
            }
          ];
        }
      );
    in
    {
      # nixosConfigurations.default = pi4SystemCross."x86_64-linux";

      packages = forAllSystems (
        system:
        mantle.lib.mkTools {
          pkgs = pkgsFor.${system};
          nixosConfig = pi4SystemCross.${system};
          updateVersion = self.shortRev or "dev";
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
          flashInstallImage = mkApp self.packages.${system}.flashInstallImage;
          activateOverlay = mkApp self.packages.${system}.activateOverlay;
          deactivateOverlay = mkApp self.packages.${system}.deactivateOverlay;
          deployUpdate = mkApp self.packages.${system}.deployUpdate;
          deployOverlay = mkApp self.packages.${system}.deployOverlay;
        }
      );
    };
}
