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
      lib.init = import ./lib self.nixosModules.default;

      nixosModules.default = import ./modules;

      checks = forAllSystems (
        system:
        import ./tests {
          pkgs = pkgsFor.${system};
          inherit self;
        }
      );

      templates = {
        basic = {
          path = ./examples/pi4;
          description = "pi4 minimal template";
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
