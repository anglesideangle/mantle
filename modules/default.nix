{
  lib,
  modulesPath,
  ...
}:
with lib;
{
  imports = [
    ./image.nix
    ./boot.nix
    ./update.nix
    ./networking.nix
    "${modulesPath}/profiles/minimal.nix"
  ];

  options.mantle = {
    enable = mkEnableOption "enable mantle image partitioning";

    overlay.enable = mkEnableOption "enable overlay";

    partitions = {
      esp = {
        label = mkOption {
          type = types.str;
          default = "boot";
        };
        format = mkOption {
          type = types.str;
          default = "vfat";
        };
        size = mkOption { type = types.str; };
      };

      store-verity = {
        label-prefix = mkOption {
          type = types.str;
          default = "store-verity";
        };
        size = mkOption { type = types.str; };
      };

      store = {
        label-prefix = mkOption {
          type = types.str;
          default = "store";
        };
        format = mkOption {
          type = types.str;
          default = "erofs";
        };
        size = mkOption { type = types.str; };
      };

      var = {
        label = mkOption {
          type = types.str;
          default = "persistent";
        };
        format = mkOption {
          type = types.str;
          default = "ext4";
        };
        size = mkOption { type = types.str; };
      };
    };
  };
}
