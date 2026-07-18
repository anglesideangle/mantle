{
  config,
  pkgs,
  lib,
}:
let
  cfg = config.partitions;
  store-label = "${cfg.store.label-prefix}_${config.system.image.version}";
  store-verity-label = "${cfg.store-verity.label-prefix}_${config.system.image.version}";

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

    esp = "esp";
    var = "var";
  };

  efiArch = config.nixpkgs.hostPlatform.efiArch;
  bootLocation = "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI";
in
rec {
  esp = {
    repartConfig = {
      Type = partitionTypes.esp;
      Label = cfg.esp.label;
      Format = cfg.esp.format;
      SizeMinBytes = cfg.esp.size;
      SizeMaxBytes = cfg.esp.size;
      SplitName = "esp";
    };
    contents.${bootLocation}.source = "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
  };

  esp-installer-copy.repartConfig = esp.repartConfig // {
    CopyBlocks = "auto";
  };

  store = {
    storePaths = [ config.system.build.toplevel ];
    repartConfig = {
      Type = partitionTypes.usr;
      Label = store-label;
      Format = cfg.store.format;
      Verity = "data";
      VerityMatchKey = "store";
      ReadOnly = "yes";
      SplitName = "store";
      SizeMinBytes = cfg.store.size;
      SizeMaxBytes = cfg.store.size;
    };
  };

  store-installer-copy.repartConfig = store.repartConfig // {
    CopyBlocks = "auto";
  };

  store-verity.repartConfig = {
    Type = partitionTypes.usr-verity;
    Label = store-verity-label;
    Verity = "hash";
    VerityMatchKey = "store";
    SplitName = "store-verity";
  };

  store-verity-copy.repartConfig = store-verity.repartConfig // {
    CopyBlocks = "auto";
  };

  empty-store.repartConfig = {
    inherit (store.repartConfig)
      Type
      SizeMinBytes
      SizeMaxBytes
      ;
    Label = "_empty";
    Minimize = "off";
  };

  empty-store-verity.repartConfig = {
    inherit (store-verity.repartConfig) Type;
    Label = "_empty";
    Minimize = "off";
  };

  var.repartConfig = {
    Type = partitionTypes.var;
    Format = cfg.var.format;
    Label = cfg.var.label;
    Minimize = "off";
    GrowFileSystem = "yes";
    Weight = "100";
    FactoryReset = "yes";
  };

  var-installer.repartConfig = {
    Type = partitionTypes.var;
    Format = cfg.var.format;
    Label = "installer-${cfg.var.label}";
    Minimize = "off";
    GrowFileSystem = "yes";
    Weight = "100";
  };
}
