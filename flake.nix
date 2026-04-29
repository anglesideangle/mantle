{
  description = "A platform for robotics applications";

  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

  outputs =
    {
      self,
      nixpkgs,
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
      lib.init = import ./lib;

      nixosModules.default = import ./modules;

      packages = forAllSystems (system: { });

      checks = forAllSystems (system: {
        modules = import ./tests {
          pkgs = pkgsFor.${system};
          modules = [ self.nixosModules.default ];
        };
      });

      templates = {
        basic = {
          path = ./examples/base;
          description = "Basic example?";
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
