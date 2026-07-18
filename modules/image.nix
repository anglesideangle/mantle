{
  lib,
  config,
  modulesPath,
  ...
}:
with lib;
let
  cfg = config.partitions;
in
{
  imports = [
    "${modulesPath}/image/repart.nix"
  ];

  config = mkIf cfg.enable {
    boot.uki.tries = 2;

    image.repart = {
      verityStore = {
        enable = true;
        partitionIds = {
          esp = "00-esp";
          store-verity = "10-store-verity";
          store = "11-store";
        };
        ukiPath = "/EFI/Linux/${config.system.boot.loader.ukiFile}";
      };
      split = true;
      compression = {
        enable = true;
        algorithm = "zstd";
      };
    };
  };
}
