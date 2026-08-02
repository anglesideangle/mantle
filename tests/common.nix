{ pkgs }:

{
  bootNodeModule =
    {
      lib,
      ...
    }:
    {
      boot.kernelParams = lib.mkDefault [ "console=ttyS0" ];
      virtualisation.memorySize = lib.mkDefault 1024;

      virtualisation = {
        directBoot.enable = lib.mkForce false;
        useEFIBoot = true;
        mountHostNixStore = false;
        useDefaultFilesystems = false;
        fileSystems = lib.mkVMOverride { };
      };

      fileSystems."/" = lib.mkVMOverride {
        device = "nodev";
        fsType = "tmpfs";
      };
    };

  diskBoot =
    image: name:
    # python
    ''
      import os
      import subprocess
      import tempfile

      ${name}_disk_image = tempfile.NamedTemporaryFile()

      subprocess.run([
        "${pkgs.qemu}/bin/qemu-img",
        "create",
        "-f",
        "qcow2",
        "-b",
        "${image}",
        "-F",
        "raw",
        ${name}_disk_image.name,
      ], check=True)

      os.environ['NIX_DISK_IMAGE'] = ${name}_disk_image.name
    '';
}
