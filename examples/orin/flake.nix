{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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

      deviceIP = "192.168.1.50";

      deviceSshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyd6eNE/R46/uTnQRpW/StRIaGc5yzO86kWeQNBny+H hello@rickastley.co.uk";

      mantleLibFor = forAllSystems (
        buildPlatform:
        mantle.lib.init pkgsFor.${buildPlatform} {
          modules = [
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
                    # gcc.arch = "armv8.2-a";
                    # gcc.tune = "cortex-a78ae";
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

                system.nixos-init.enable = lib.mkForce false;
                system.etc.overlay.enable = lib.mkForce false;

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

                # jetson orin supports uefi
                boot.loader.systemd-boot.enable = true;

                mantle = {
                  enable = true;
                  name = "mantle-orin";
                  version = "${toString self.lastModified}-${self.shortRev or "dev"}";
                  overlay.enable = true;
                  partitions = {
                    esp.size = "128M";
                    store.size = "5G";
                    store-verity.size = "275M";
                    var.size = "5G";
                  };
                };

                networking.hostName = "mantle-orin";

                boot.initrd.systemd.emergencyAccess = true;
                users.users.root.password = "!";
                users.users.root.openssh.authorizedKeys.keys = [ deviceSshPublicKey ];

                networking = {
                  useDHCP = false;
                  interfaces."eth0" = {
                    useDHCP = false;
                    ipv4.addresses = [
                      {
                        address = deviceIP;
                        prefixLength = 24;
                      }
                    ];
                  };
                };

                services.openssh = {
                  enable = true;
                  settings.PasswordAuthentication = false;
                };
              }
            )
          ];
        }
      );
    in
    {
      packages = lib.recursiveUpdate (forAllSystems (system: mantleLibFor.${system})) {
        "x86_64-linux" = {
          inherit (jetpack.packages."x86_64-linux") flash-orin-agx-devkit;
        };
      };

      devShells = forAllSystems (system: {
        default = pkgsFor.${system}.mkShellNoCC {
          DEVICE_URL = "root@${deviceIP}";
          SSH_KEY = "~/.ssh/mantle-test";
        };
      });

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
            clear-overlay = mkApp self.packages.${system}.clear-overlay;
            deploy-update = mkApp self.packages.${system}.deploy-update;
            deploy-overlay = mkApp self.packages.${system}.deploy-overlay;
          }))
          {
            "x86_64-linux".flash-orin-agx-devkit = mkApp self.packages."x86_64-linux".flash-orin-agx-devkit;
          };
    };
}
