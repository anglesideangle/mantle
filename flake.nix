{
  description = "A platform for robotics applications";

  # inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  inputs.nixpkgs.url = "github:anglesideangle/nixpkgs/fix-repart-formatting";

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
      lib.init = import ./.;

      nixosModules.default = import ./modules;

      checks = forAllSystems (
        system:
        import ./tests {
          pkgs = pkgsFor.${system};
          inherit self;
        }
      );

      templates = {
        pi4 = {
          path = ./examples/pi4;
          description = "pi4 minimal template";
        };
        orin = {
          path = ./examples/orin;
          description = "jetson orin minimal template";
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
