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
      compression = {
        enable = true;
        algorithm = "zstd";
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

      esp-installer-copy.repartConfig = defs.esp.repartConfig // {
        CopyBlocks = "auto";
      };

      store = {
        storePaths = [ config.system.build.toplevel ];
        repartConfig = {
          Type = partitionTypes.usr;
          Label = storeLabel;
          Format = cfg.store.format;
          Verity = "data";
          VerityMatchKey = "store";
          ReadOnly = "yes";
          SplitName = "store";
          SizeMinBytes = cfg.store.size;
          SizeMaxBytes = cfg.store.size;
        };
      };

      store-installer-copy.repartConfig = defs.store.repartConfig // {
        CopyBlocks = "auto";
      };

      store-verity.repartConfig = {
        Type = partitionTypes.usr-verity;
        Label = storeVerityLabel;
        Verity = "hash";
        VerityMatchKey = "store";
        SplitName = "store-verity";
      };

      store-verity-copy.repartConfig = defs.store-verity.repartConfig // {
        CopyBlocks = "auto";
      };

      empty-store.repartConfig = {
        inherit (defs.store.repartConfig)
          Type
          SizeMinBytes
          SizeMaxBytes
          ;
        Label = "_empty";
        Minimize = "off";
      };

      empty-store-verity.repartConfig = {
        inherit (defs.store-verity.repartConfig) Type;
        Label = "_empty";
        Minimize = "off";
      };

      var.repartConfig = {
        Type = partitionTypes.var;
        Format = cfg.var.format;
        Label = cfg.var.label;
        Minimize = "off";
        GrowFileSystem = "yes";
        Weight = "100";
        FactoryReset = "yes";
      }
      // optionalAttrs (cfg.var.size != null) {
        SizeMinBytes = cfg.var.size;
      };

      var-installer.repartConfig = {
        Type = partitionTypes.var;
        Format = cfg.var.format;
        Label = "installer-${cfg.var.label}";
        Minimize = "off";
        GrowFileSystem = "yes";
        Weight = "100";
      };
    };

    # mkInstaller depends on systemd utils, which requires a module system :(
    system.build._mkInstaller = import ../lib/mk-installer.nix { inherit pkgs lib utils; };
  };
}
