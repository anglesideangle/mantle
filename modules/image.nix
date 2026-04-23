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

  config = mkIf cfg.enable {
    # /usr is read-only in this image layout.
    # Skip creating /usr/bin/env in both initrd switch-root and activation.
    environment.usrbinenv = mkForce null;
    system.activationScripts.usrbinenv = mkForce "";

    image.repart = {
      name = config.system.image.id;

      verityStore = {
        enable = true;
        partitionIds = {
          esp = cfg.esp.id;
          store-verity = cfg.store-verity.id;
          store = cfg.store.id;
        };
      };

      partitions = mkMerge [
        {
          ${cfg.esp.id} =
            let
              inherit (pkgs.stdenv.hostPlatform) efiArch;
            in
            {
              # image.repart.verityStore already handles /EFI/Linux/${ukiFile}
              contents."/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source =
                "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
              repartConfig = {
                Type = "esp";
                Label = "boot";
                Format = cfg.esp.format;
                SizeMinBytes = cfg.esp.size;
                SplitName = "-";
              };
            };

          ${cfg.store.id} = {
            storePaths = [ config.system.build.toplevel ];
            # nixStorePrefix = "/";
            repartConfig = mkMerge [
              {
                Label = store-label;
                Format = cfg.store.format;
                ReadOnly = "yes";
                SplitName = "store";
              }
              (mkIf (!cfg.isInstaller) {
                SizeMinBytes = cfg.store.size;
                SizeMaxBytes = cfg.store.size;
              })
              (mkIf (cfg.isInstaller) {
                Minimize = "best";
              })
            ];
          };

          ${cfg.store-verity.id}.repartConfig = {
            Label = store-verity-label;
            SplitName = "store-verity";
          };
        }
        (mkIf (!cfg.isInstaller) {
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
            SizeMinBytes = cfg.var.size;
            SizeMaxBytes = cfg.var.size;
            SplitName = "-";
            FactoryReset = "yes";
          };
        })
      ];
    };
  };
}
