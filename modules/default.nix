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

  options.partitions = {
    enable = mkEnableOption "partitioning";

    esp = {
      label = mkOption {
        type = types.str;
        default = "boot";
      };
      format = mkOption {
        type = types.str;
        default = "vfat";
      };
      size = mkOption {
        type = types.str;
      };
    };

    store-verity = {
      label-prefix = mkOption {
        type = types.str;
        default = "store-verity";
      };
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
      size = mkOption {
        type = types.str;
      };
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
      size = mkOption {
        type = types.str;
        default = null;
      };
    };
  };
}
