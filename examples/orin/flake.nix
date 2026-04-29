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

      pi4SystemCross = forAllSystems (
        buildPlatform:
        lib.nixosSystem {
          modules = [
            mantle.nixosModules.default
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
                };

                # l4t kernel doesn't have erofs, which is the file type of our store partition
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

                # L4T 5.15 overlayfs rejects the data-only lowerdir separator
                # ("::") used by the default initrd /etc overlay mount.
                # Keep metacopy/redirect_dir, but use a single lowerdir ":".
                # boot.initrd.systemd.mounts = lib.mkBefore [
                #   {
                #     what = "overlay";
                #     where = "/sysroot/etc";
                #     type = "overlay";
                #     options = "nodev,nosuid,relatime,redirect_dir=on,metacopy=on,lowerdir=/run/nixos-etc-metadata:/etc-basedir,ro";

                #     requiredBy = [ "initrd-fs.target" ];
                #     before = [ "initrd-fs.target" ];
                #     requires = [ "initrd-find-etc.service" ];
                #     after = [ "initrd-find-etc.service" ];

                #     unitConfig = {
                #       RequiresMountsFor = [
                #         "/sysroot/nix/store"
                #         "/run/nixos-etc-metadata"
                #       ];
                #       DefaultDependencies = false;
                #     };
                #   }
                # ];

                # sad
                system.nixos-init.enable = lib.mkForce false;
                system.etc.overlay.enable = lib.mkForce false;

                partitions = {
                  enable = true;
                  esp.size = "256M";
                  store.size = "10G";
                  var.size = "2G";
                };

                system.image.id = "imageid";
                boot.uki.name = "ukiname";
                networking.hostName = "mantle-target";

                boot.initrd.systemd.emergencyAccess = true;
                users.users.root.password = "password";
                # users.users.root.initialPassword = "password";
              }
            )
          ];
        }
      );
    in
    {
      # nixosConfigurations.default = pi4SystemCross."x86_64-linux";

      packages =
        lib.recursiveUpdate
          (forAllSystems (
            system:
            mantle.lib.mkTools {
              pkgs = pkgsFor.${system};
              nixosConfig = pi4SystemCross.${system};
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
            flashInstallImage = mkApp self.packages.${system}.flashInstallImage;
            activateOverlay = mkApp self.packages.${system}.activateOverlay;
            deactivateOverlay = mkApp self.packages.${system}.deactivateOverlay;
            deployUpdate = mkApp self.packages.${system}.deployUpdate;
            deployOverlay = mkApp self.packages.${system}.deployOverlay;
          }))
          {
            "x86_64-linux".flash-orin-agx-devkit = mkApp self.packages."x86_64-linux".flash-orin-agx-devkit;
          };
    };
}
