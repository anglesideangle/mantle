{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    mantle.url = "files:///home/asa/Projects/mantle";
    mantle.nixpkgs.follows = "nixpkgs";
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
    in
    {
      nixosModules.default = import ./modules;
      nixosConfiguration.default = nixpkgs.lib.nixosSystem {
        modules = [
          mantle.nixosModules.default
          nixos-hardware.nixosModules.raspberry-pi-4
          # { }
        ];
      };

      packages = forAllSystems (system: {
        # cli tool:
        # - build image : config.image -> xz
        # - flash : ( build image -> write to device )
        # - deploy image ( build image -> copy to /var/updates, delete upper)
        # - deploy overlay ( copy overlay toplevel -> mount overlayfs /var/nix/upper )
        # - activate overlay ( copy overlay toplevel -> mount overlayfs /var/nix/upper )
        # - deactivate overlay ( destroy overlayfs )
      });
    };
}
