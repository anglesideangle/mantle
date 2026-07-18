{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    mantle = {
      url = "path:/home/asa/Projects/mantle";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    jetpack = {
      url = "github:anduril/jetpack-nixos/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      mantle,
      jetpack,
    }:
    let
      allSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs allSystems;
      pkgsFor = forAllSystems (system: nixpkgs.legacyPackages.${system});

      inherit (nixpkgs) lib;

      orinModules = buildPlatform: [
        jetpack.nixosModules.default
        (
          { lib, ... }:
          let
            inherit (lib.kernel) yes module;
          in
          {
            nixpkgs = {
              inherit buildPlatform;
              hostPlatform = {
                system = "aarch64-linux";
                gcc.arch = "armv8.2-a";
                gcc.tune = "cortex-a78ae";
              };
              overlays = [
                (final: prev: {
                  config =
                    prev.config
                    // (
                      if prev.stdenv.hostPlatform.isAarch64 then
                        { }
                      else
                        {
                          cudaSupport = false;
                          cudaCapabilities = [ ];
                        }
                    );
                })
              ];
            };

            boot.kernelPatches = [
              {
                name = "enable-erofs";
                patch = null;
                structuredExtraConfig = {
                  EROFS_FS = yes;

                  EROFS_FS_XATTR = yes;
                  EROFS_FS_POSIX_ACL = yes;
                  EROFS_FS_SECURITY = yes;

                  EROFS_FS_ZIP = yes;
                };
              }
              {
                name = "enable-tpm-crb";
                patch = null;
                structuredExtraConfig = {
                  TCG_TPM = yes;
                  TCG_TIS_CORE = yes;
                  TCG_CRB = module;
                  TCG_TIS = module;
                };
              }
            ];

            hardware.nvidia-jetpack.enable = true;
            hardware.nvidia-jetpack.som = "orin-agx";
            hardware.nvidia-jetpack.carrierBoard = "devkit";

            hardware.graphics.enable = true;

            hardware.nvidia-jetpack.kernel.realtime = true;

            system.nixos-init.enable = lib.mkForce false;
            system.etc.overlay.enable = lib.mkForce false;

            partitions = {
              enable = true;
              esp.size = "256M";
              store.size = "10G";
              var.size = "2G";
            };

            system.image.id = "imageid";
            system.image.version = self.shortRev or "dev";
            boot.uki.name = "ukiname";
            networking.hostName = "mantle-target";

            boot.initrd.systemd.emergencyAccess = true;
            users.users.root.password = "password";
          }
        )
      ];
    in
    {
      packages =
        lib.recursiveUpdate
          (forAllSystems (
            buildPlatform:
            mantle.lib.init {
              pkgs = pkgsFor.${buildPlatform};
              modules = orinModules buildPlatform;
              updateVersion = self.shortRev or "dev";
            }
          ))
          {
            "x86_64-linux" = {
              inherit (jetpack.packages."x86_64-linux") flash-orin-agx-devkit;
            };
          };

      apps =
        let
          mkApp = drv: {
            type = "app";
            program = nixpkgs.lib.getExe drv;
          };
        in
        lib.recursiveUpdate
          (forAllSystems (system: {
            flash-to-device = mkApp self.packages.${system}.flash-to-device;
            flash-installer-to-device = mkApp self.packages.${system}.flash-installer-to-device;
            activate-overlay = mkApp self.packages.${system}.activate-overlay;
            deactivate-overlay = mkApp self.packages.${system}.deactivate-overlay;
            deploy-update = mkApp self.packages.${system}.deploy-update;
            deploy-overlay = mkApp self.packages.${system}.deploy-overlay;
          }))
          {
            "x86_64-linux".flash-orin-agx-devkit = mkApp self.packages."x86_64-linux".flash-orin-agx-devkit;
          };
    };
}