{ lib, config, ... }:
let
  cfg = config.mantle;
in
with lib;
{
  config.systemd.sysupdate = mkIf cfg.image.enable {
    enable = true;

    transfers = {
      "10-uki" = {
        Source = {
          MatchPattern = [
            "${config.boot.uki.name}-@v.efi.xz"
          ];
          Path = "/var/updates/";
          Type = "regular-file";
        };
        Target = {
          InstancesMax = 2;
          MatchPattern = [
            "${config.boot.uki.name}-@v.efi"
          ];
          Mode = "0444";
          Path = "/EFI/Linux";
          PathRelativeTo = "boot";
          Type = "regular-file";
        };
        Transfer = {
          ProtectVersion = "%A";
        };
      };

      "20-store" = {
        Source = {
          MatchPattern = [
            "store-@v.img.xz"
          ];
          Path = "/var/updates/";
          Type = "regular-file";
        };

        Target = {
          InstancesMax = 2;
          Path = "auto";
          MatchPattern = "store-@v";
          Type = "partition";
          ReadOnly = "yes";
        };

        Transfer = {
          ProtectVersion = "%A";
        };
      };
    };
  };
}
