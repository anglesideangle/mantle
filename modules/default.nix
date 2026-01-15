{ lib, config, ... }:
let
  cfg = config.mantle;
in
with lib;
{
  imports = [
    ./filesystem.nix
    ./repart.nix
    ./sysupdate.nix
    ./generic.nix
  ];

  options.mantle = {
    image = {
      enable = mkEnableOption "Immutable A/B disk partitioning and update system";

      # name = mkOption {
      #   type = types.str;
      #   description = "Name for the current system image.";
      # };

      # version = mkOption {
      #   type = types.str;
      #   description = "Version string for the current system image (used for updating logic).";
      # };

      partitions = {
        esp = {
          size = mkOption {
            type = types.str;
            default = "200M";
            description = ''
              Specify the size of the ESP partition.
            '';
          };
          id = mkOption {
            type = types.str;
            default = "00-esp";
            description = ''
              Specify the attribute name of the ESP partition.
            '';
          };
        };
        store-verity = {
          id = mkOption {
            type = types.str;
            default = "00-esp";
            description = ''
              Specify the attribute name of the store's dm-verity hash partition.
            '';
          };
        };
        store = {
          size = mkOption {
            type = types.str;
            default = "5G";
            description = ''
              Specify the size of the store A and B partitions.
            '';
          };
          id = mkOption {
            type = types.str;
            default = "20-store";
            description = ''
              Specify the attribute name of the store partition.
            '';
          };
          format = mkOption {
            type = types.enum [
              "erofs"
              "squashfs"
            ];
            default = "erofs";
            description = "The filesystem of the immutable root partition.";
          };
        };
        var = {
          size = mkOption {
            type = types.str;
            default = "5G";
            description = ''
              Specify the size of the mutable var partition.
            '';
          };
          id = mkOption {
            type = types.str;
            default = "30-var";
            description = ''
              Specify the attribute name of the store partition.
            '';
          };
          format = mkOption {
            type = types.enum [
              "ext4"
              "btrfs"
              "xfs"
              "zfs"
            ];
            default = "ext4";
            description = "The filesystem of the mutable /var partition.";
          };
        };
      };

    };

    storeOverlay = {
      enable = mkEnableOption "Mutable /nix/store overlay and update system";
    };
  };

  config.assertions = [
    {
      assertion = cfg.image.enable || !cfg.storeOverlay.enable;
      message = "The mantle store overlay can only be enabled along with the immutable image option (`mantle.image.enable = true`).";
    }
  ];
}
