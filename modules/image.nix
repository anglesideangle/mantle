{
  pkgs,
  lib,
  config,
  modulesPath,
  utils,
  ...
}:
with lib;
let
  cfg = config.partitions;
  defs = config.system.build._partitionDefs;

  storeLabel = "${cfg.store.label-prefix}_${config.system.image.version}";
  storeVerityLabel = "${cfg.store-verity.label-prefix}_${config.system.image.version}";

  partitionTypes = {
    usr =
      {
        "x86_64" = "usr-x86-64";
        "arm64" = "usr-arm64";
      }
      ."${pkgs.stdenv.hostPlatform.linuxArch}";

    usr-verity =
      {
        "x86_64" = "usr-x86-64-verity";
        "arm64" = "usr-arm64-verity";
      }
      ."${pkgs.stdenv.hostPlatform.linuxArch}";

    esp = "esp";
    var = "var";
  };

  efiArch = config.nixpkgs.hostPlatform.efiArch;
  bootLocation = "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI";
in
{
  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  config = mkIf cfg.enable {
    boot.uki.tries = 2;

    image.repart = {
      verityStore = {
        enable = true;
        partitionIds = {
          esp = "00-esp";
          store-verity = "10-store-verity";
          store = "11-store";
        };
        ukiPath = "/EFI/Linux/${config.system.boot.loader.ukiFile}";
      };
      split = true;
      partitions = {
        "00-esp" = defs.esp;
        "10-store-verity" = defs.store-verity;
        "11-store" = defs.store;
      };
    };

    system.build._partitionDefs = {
      esp = {
        repartConfig = {
          Type = partitionTypes.esp;
          Label = cfg.esp.label;
          Format = cfg.esp.format;
          SizeMinBytes = cfg.esp.size;
          SizeMaxBytes = cfg.esp.size;
          SplitName = "esp";
        };
        contents.${bootLocation}.source = "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
      };

      store = {
        storePaths = [ config.system.build.toplevel ];
        repartConfig = {
          Type = partitionTypes.usr;
          Label = storeLabel;
          Format = cfg.store.format;
          # Compression = "zstd";
          Verity = "data";
          VerityMatchKey = "store";
          ReadOnly = "yes";
          Minimize = "off";
          SplitName = "store";
          SizeMinBytes = cfg.store.size;
          SizeMaxBytes = cfg.store.size;
        };
      };

      store-verity.repartConfig = {
        Type = partitionTypes.usr-verity;
        Label = storeVerityLabel;
        Verity = "hash";
        VerityMatchKey = "store";
        Minimize = "off";
        SplitName = "store-verity";
        # VerityHashBlockSizeBytes = "4096";
        # VerityDataBlockSizeBytes = "4096";
        SizeMinBytes = cfg.store-verity.size;
        SizeMaxBytes = cfg.store-verity.size;
      };

      empty-store.repartConfig = {
        inherit (defs.store.repartConfig) Type SizeMinBytes SizeMaxBytes;
        Label = "_empty";
        SplitName = "store-empty";
        Minimize = "off";
      };

      empty-store-verity.repartConfig = {
        inherit (defs.store-verity.repartConfig) Type SizeMinBytes SizeMaxBytes;
        Label = "_empty";
        SplitName = "store-verity-empty";
        Minimize = "off";
      };

      var.repartConfig = {
        Type = partitionTypes.var;
        Format = cfg.var.format;
        Label = cfg.var.label;
        Minimize = "off";
        # GrowFileSystem = "yes";
        Weight = "1000";
        FactoryReset = "yes";
      }
      // optionalAttrs (cfg.var.size != null) {
        SizeMinBytes = cfg.var.size;
      };

      var-installer.repartConfig = {
        Type = partitionTypes.var;
        Format = cfg.var.format;
        Label = cfg.var.label;
        Minimize = "off";
        # GrowFileSystem = "yes";
        Weight = "1000";
      };
    };

    # mkInstaller depends on systemd utils, which requires a module system :(
    system.build._mkInstallerHostPlatform = import ../lib/mk-installer.nix { inherit pkgs lib utils; };
    system.build._mkInstallerBuildPlatform = import ../lib/mk-installer.nix {
      inherit lib utils;
      pkgs = pkgs.buildPackages;
    };
  };
}
