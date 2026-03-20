{ pkgs, ... }:
{
  name = "boot-test";

  nodes.machine =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      partitions = {
        enable = true;
        esp.size = "128M";
        store.size = "1024M";
      };
      system.image = {
        id = "mantle-test";
        version = pkgs.lib.trivial.release;
      };
      boot.uki.name = "test";

      # -------------------------------------------------------------
      # 2. Mock the Hardware (VM Compatibility Layer)
      # -------------------------------------------------------------

      # QEMU doesn't have your partitions. We force the test VM to use
      # its own volatile disks for the critical paths so it doesn't hang.

      fileSystems."/" = lib.mkForce {
        device = "tmpfs";
        fsType = "tmpfs";
      };

      fileSystems."/var" = lib.mkForce {
        device = "tmpfs";
        fsType = "tmpfs";
      };

      # We also need to disable the specific 'bind' or 'overlay' mounts
      # defined in your module because they depend on the specific
      # structure of the EROFS root which doesn't exist here.
      fileSystems."/nix/store" = lib.mkForce {
        device = "host_store";
        fsType = "9p";
        options = [
          "trans=virtio"
          "version=9p2000.L"
          "cache=loose"
        ];
      };

      fileSystems."/nix/.ro-store" = lib.mkForce {
        device = "host_store";
        fsType = "9p";
        options = [
          "trans=virtio"
          "version=9p2000.L"
          "cache=loose"
        ];
      };

      fileSystems."/boot" = lib.mkForce {
        device = "tmpfs";
        fsType = "tmpfs";
      };

      # Disable the initrd sanitization service for this basic test
      # because it will fail to find the /sysroot/.ro-store paths.
      boot.initrd.systemd.services.sanitize-overlay.enable = lib.mkForce false;
    };

  # -------------------------------------------------------------
  # 3. The Test Script
  # -------------------------------------------------------------
  testScript = ''
    import re

    # 1. Wait for boot
    machine.wait_for_unit("multi-user.target")
    machine.succeed("echo 'Mantle System Booted Successfully!'")

    # 2. Check /etc/os-release
    #    'system.image.version' sets the IMAGE_VERSION field in this file.
    os_release = machine.succeed("cat /etc/os-release")
    print(os_release) # Useful for debugging in the log

    # Verify image version is present and not the old pinned test value
    match = re.search(r'^IMAGE_VERSION="([^"]+)"$', os_release, re.MULTILINE)
    assert match is not None
    assert match.group(1) != "0.0.1"
  '';
}
