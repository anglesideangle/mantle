{
  lib,
  pkgs,
  config,
  modulesPath,
  ...
}:
with lib;
let
  cfg = config.partitions;
  store-label = "${cfg.store.label-prefix}_${config.system.image.version}";
  store-verity-label = "${cfg.store-verity.label-prefix}_${config.system.image.version}";
in
{
  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  # boot.uki.tries = 2;
  config.image.repart =
    let
      efiArch = config.nixpkgs.hostPlatform.efiArch;
      bootLocation = "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI";
    in
    mkIf cfg.enable {
      name = config.system.image.id;

      verityStore = {
        enable = true;
        partitionIds = {
          esp = cfg.esp.id;
          store-verity = cfg.store-verity.id;
          store = cfg.store.id;
        };
        ukiPath = "/EFI/Linux/${config.system.boot.loader.ukiFile}";
      };

      partitions = {
        ${cfg.esp.id} = {
          repartConfig = {
            Type = "esp";
            Label = "boot";
            Format = cfg.esp.format;
            SplitName = "-";
            # Minimize = "off";
            SizeMinBytes = cfg.esp.size;
            SizeMaxBytes = cfg.esp.size;
          };
          contents.${bootLocation}.source = "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
        };

        ${cfg.store.id} = {
          storePaths = [ config.system.build.toplevel ];
          repartConfig = {
            Label = store-label;
            Format = cfg.store.format;
            ReadOnly = "yes";
            SplitName = "store";
            SizeMinBytes = cfg.store.size;
            SizeMaxBytes = cfg.store.size;
          };
        };

        ${cfg.store-verity.id}.repartConfig = {
          Label = store-verity-label;
          SplitName = "store-verity";
        };

        # store needs has a static size for a/b updates
        # ${cfg.store.id}.repartConfig = {
        #   SizeMinBytes = cfg.store.size;
        #   SizeMaxBytes = cfg.store.size;
        # };

        ${cfg.empty-store.id}.repartConfig = {
          inherit (config.image.repart.partitions.${cfg.store.id}.repartConfig)
            Type
            SizeMinBytes
            SizeMaxBytes
            ;
          Label = "_empty";
          # Format = "empty";
          Minimize = "off";
          SplitName = "-";
        };

        ${cfg.empty-store-verity.id}.repartConfig = {
          inherit (config.image.repart.partitions.${cfg.store-verity.id}.repartConfig) Type;
          Label = "_empty";
          # Format = "empty";
          Minimize = "off";
          SplitName = "-";
        };

        ${cfg.var.id}.repartConfig = {
          Type = "var";
          Format = cfg.var.format;
          Label = cfg.var.label;
          Minimize = "off";
          # SizeMinBytes = cfg.var.size;
          GrowFileSystem = "yes";
          Weight = "100";
          # SizeMaxBytes = cfg.var.size;
          SplitName = "-";
          FactoryReset = "yes";
        };
      };
    };
}
