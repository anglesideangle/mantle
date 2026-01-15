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
      # -------------------------------------------------------------
      # 1. Enable your Platform
      # -------------------------------------------------------------
      mantle.image = {
        enable = true;
        name = "test-robot";
        version = "0.0.1";
      };

      # Enable the overlay logic to verify the service generates correctly
      mantle.storeOverlay.enable = true;

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

      # Disable the initrd sanitization service for this basic test
      # because it will fail to find the /sysroot/.ro-store paths.
      boot.initrd.systemd.services.sanitize-overlay.enable = lib.mkForce false;
    };

  # -------------------------------------------------------------
  # 3. The Test Script
  # -------------------------------------------------------------
  testScript = ''
    # 1. Wait for boot
    machine.wait_for_unit("multi-user.target")
    machine.succeed("echo 'Mantle System Booted Successfully!'")

    # 2. Check /etc/os-release
    #    'system.image.version' sets the IMAGE_VERSION field in this file.
    os_release = machine.succeed("cat /etc/os-release")
    print(os_release) # Useful for debugging in the log

    # Verify our version string is present
    assert 'IMAGE_VERSION="0.0.1"' in os_release
  '';
}
