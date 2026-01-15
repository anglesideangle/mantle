{
  description = "A platform for robotics applications";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      allSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs allSystems;
      pkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in
    {
      nixosModules.default =
        { modulesPath, ... }:
        {
          imports = [
            ./modules
            "${modulesPath}/image/repart.nix"
          ];
        };

      checks = forAllSystems (
        system:
        import ./tests {
          pkgs = pkgsFor.${system};
          modules = [ self.nixosModules.default ];
        }
      );

      devShells = forAllSystems (system: {
        default = pkgsFor.${system}.mkShellNoCC {
          inputsFrom = [ self.formatter.${system} ];
          packages = with pkgsFor.${system}; [
            nixd
            self.formatter.${system}
          ];
        };
      });

      formatter = forAllSystems (
        system:
        pkgsFor.${system}.treefmt.withConfig {
          name = "project-format";

          runtimeInputs = with pkgsFor.${system}; [
            nixfmt
          ];

          settings = {
            formatter.nix = {
              command = "nixfmt";
              includes = [ "*.nix" ];
            };
          };
        }
      );
    };
}
