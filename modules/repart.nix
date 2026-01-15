{
  lib,
  pkgs,
  config,
  modulesPath,
  ...
}:
let
  cfg = config.mantle;
  partCfg = cfg.image.partitions;
in
with lib;
{

  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  config = mkIf cfg.image.enable {
    # Repart is useful for immutable os images because it allows them to "expand"
    # into the full disk at boot, despite being immutable and copied directly
    # onto their disk.
    #
    # This config sets up a boot partition, two a/b read only `/nix/store`
    # partitions, and a `/var` for persistent data
    image.repart =
      let
        inherit (pkgs.stdenv.hostPlatform) efiArch;
      in
      {
        name = config.system.image.id;

        # automatically configures 00-esp, 10-store-verity, 20-store partitions
        # and dm-verity in initrd
        # verityStore = {
        #   enable = true;
        #   partitionIds = {
        #     esp = partCfg.esp.id;
        #     store-verity = partCfg.store-verity.id;
        #     store = partCfg.store.id;
        #   };
        # };

        partitions = {
          ${partCfg.esp.id} = {
            contents = {
              "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
                "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

              "/EFI/Linux/${config.system.boot.loader.ukiFile}".source =
                "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
            };
            repartConfig = {
              Type = "esp";
              Label = "boot";
              Format = "vfat";
              SizeMinBytes = partCfg.esp.size;
              SplitName = "-";
            };
          };

          ${partCfg.store.id} = {
            storePaths = [ config.system.build.toplevel ];
            nixStorePrefix = if cfg.storeOverlay.enable then "/nix/.ro-store" else "/nix/store";
            repartConfig = {
              Type = "root";
              Label = "root-${config.system.image.version}";
              SizeMinBytes = partCfg.store.size;
              SizeMaxBytes = partCfg.store.size;
              Format = partCfg.store.format;
              ReadOnly = "yes";
              SplitName = "store";
            };
          };

          empty.repartConfig = {
            Type = "root";
            Label = "_empty";
            Minimize = "off";
            SizeMinBytes = partCfg.store.size;
            SizeMaxBytes = partCfg.store.size;
            SplitName = "-";
          };

          ${partCfg.var.id}.repartConfig = {
            Type = "var";
            Format = partCfg.var.format;
            Label = "nixos-persistent";
            Minimize = "off";

            # Has to be large enough to hold zipped update files.
            SizeMinBytes = partCfg.var.size;
            SizeMaxBytes = partCfg.var.size;
            SplitName = "-";

            # Wiping this gives us a clean state.
            FactoryReset = "yes";
          };

        };
      };
  };
}
