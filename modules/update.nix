{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.mantle;
  storePrefix = cfg.partitions.store.label-prefix;
  storeVerityPrefix = cfg.partitions.store-verity.label-prefix;
  sourcePrefix = config.image.repart.name;

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
  };
in
{
  config = lib.mkIf cfg.enable {

    systemd.tmpfiles.rules = [
      "d /var/updates 0775 root root -"
    ];

    systemd.sysupdate = {
      enable = true;

      transfers = {
        "10-store" = {
          Source = {
            MatchPattern = [ "${sourcePrefix}_@v.store_@u.raw.zst" ];
            Path = "/var/updates/";
            Type = "regular-file";
          };
          Target = {
            Type = "partition";
            Path = "auto";
            MatchPattern = [ "${storePrefix}_@v" ];
            MatchPartitionType = partitionTypes.usr;
            InstancesMax = 2;
            ReadOnly = "yes";
          };
          Transfer = {
            ProtectVersion = "%A";
          };
        };

        "20-store-verity" = {
          Source = {
            MatchPattern = [ "${sourcePrefix}_@v.store-verity_@u.raw.zst" ];
            Path = "/var/updates/";
            Type = "regular-file";
          };
          Target = {
            Type = "partition";
            Path = "auto";
            MatchPattern = [ "${storeVerityPrefix}_@v" ];
            MatchPartitionType = partitionTypes.usr-verity;
            InstancesMax = 2;
            ReadOnly = "yes";
          };
        };

        "30-uki" = {
          Source = {
            MatchPattern = [ "${config.boot.uki.name}_@v+@t.efi.zst" ];
            Path = "/var/updates/";
            Type = "regular-file";
          };
          Target = {
            Type = "regular-file";
            Path = "/EFI/Linux";
            PathRelativeTo = "boot";
            MatchPattern = [ "${config.boot.uki.name}_@v+@t.efi" ];
            Mode = "0444";
            InstancesMax = 2;
          };
        };
      };
    };
  };
}
