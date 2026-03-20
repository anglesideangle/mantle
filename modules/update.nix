{ lib, config, ... }:
let
  cfg = config.partitions;
in
{
  systemd.sysupdate = lib.mkIf cfg.enable {
    enable = true;

    transfers = {
      "10-store" = {
        Source = {
          MatchPattern = [ "store-@v.img.xz" ];
          Path = "/var/updates/";
          Type = "regular-file";
        };
        Target = {
          Type = "partition";
          Path = "auto"; # TODO breaks?
          # Path = "/nix/.ro-store";
          MatchPattern = [ "store-@v" ];
          # MatchPartitionType = "";
          InstancesMax = 2;
          ReadOnly = "yes";
        };
        Transfer = {
          ProtectVersion = "%A";
        };
      };

      "20-store-verity" = {
        Source = {
          MatchPattern = [ "store-@v.verity.img.xz" ];
          Path = "/var/updates/";
          Type = "regular-file";
        };
        Target = {
          Type = "partition";
          Path = "auto";
          MatchPattern = [ "store-@v-verity" ];
          InstancesMax = 2;
          ReadOnly = "yes";
        };
      };

      "30-uki" = {
        Source = {
          MatchPattern = [ "${config.boot.uki.name}-@v.efi.xz" ];
          Path = "/var/updates/";
          Type = "regular-file";
        };
        Target = {
          Type = "regular-file";
          Path = "/EFI/Linux";
          PathRelativeTo = "boot";
          MatchPattern = [ "${config.boot.uki.name}-@v.efi" ];
          Mode = "0444";
          InstancesMax = 2;
        };
      };
    };
  };
}
