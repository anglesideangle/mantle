{
  description = "A platform for robotics applications";

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      inherit (nixpkgs) lib;

      allSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs allSystems;
      pkgsFor = forAllSystems (system: nixpkgs.legacyPackages.${system});

      mkImage =
        pkgs:
        (self.lib.init pkgs {
          modules = [
            {
              nixpkgs = { inherit (pkgs.stdenv) hostPlatform buildPlatform; };

              system.image = {
                id = "mantle";
                version = "1";
              };

              mantle = {
                enable = true;
                partitions = {
                  esp.size = "64M";
                  store.size = "1024M";
                  store-verity.size = "64M";
                  var.size = "128M";
                };
              };
            }
          ];
        }).fullPartitions;
    in
    {
      lib.init = import ./.;

      nixosModules.default = import ./modules;

      checks = {
        x86_64-linux =
          (import ./tests { pkgs = pkgsFor.x86_64-linux; })
          // (lib.mapAttrs' (name: drv: lib.nameValuePair "aarch64-${name}" drv) (
            import ./tests { pkgs = pkgsFor.x86_64-linux.pkgsCross.aarch64-multiplatform; }
          ));
        aarch64-linux = {
          image-aarch64 = mkImage pkgsFor.aarch64-linux;
          image-x86_64 = mkImage pkgsFor.aarch64-linux.pkgsCross.gnu64;
        };
      };

      templates = {
        orin = {
          path = ./examples/orin;
          description = "jetson orin template";
        };
      };

      devShells = forAllSystems (system: {
        default = pkgsFor.${system}.mkShellNoCC {
          packages = with pkgsFor.${system}; [
            nil
            nixd
            nixfmt
            self.formatter.${system}
          ];
        };
      });

      formatter = forAllSystems (system: pkgsFor.${system}.nixfmt-tree);
    };
}
