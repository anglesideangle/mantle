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
      id = mkOption {
        type = types.str;
        default = "00-esp";
      };
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
      id = mkOption {
        type = types.str;
        default = "10-store-verity";
      };
      label-prefix = mkOption {
        type = types.str;
        default = "store-verity";
      };
    };

    store = {
      id = mkOption {
        type = types.str;
        default = "20-store";
      };
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

    empty-store-verity.id = mkOption {
      type = types.str;
      default = "30-empty-store-verity";
    };

    empty-store.id = mkOption {
      type = types.str;
      default = "40-empty-store";
    };

    var = {
      id = mkOption {
        type = types.str;
        default = "50-var";
      };
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
      };
    };
  };
}
