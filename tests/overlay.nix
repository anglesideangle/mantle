{
  pkgs,
  self,
}:
let
  common = import ./common.nix { inherit pkgs; };

  imageName = "mantle-test";
  image1Version = "1";
  image2Version = "2";

  deviceConfig =
    { lib, ... }:
    {
      nixpkgs = { inherit (pkgs.stdenv) hostPlatform buildPlatform; };

      boot.loader.systemd-boot.enable = true;

      boot.initrd.availableKernelModules = [
        "virtio_pci"
        "virtio_blk"
      ];

      mantle = {
        enable = true;
        name = imageName;
        overlay.enable = true;
        partitions = {
          esp.size = "64M";
          store.size = "1024M";
          store-verity.size = "64M";
          var.size = "128M";
        };
      };

      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = lib.mkForce false;
          PermitRootLogin = "prohibit-password";
        };
        hostKeys = [
          {
            type = "ed25519";
            path = "/var/ssh/ssh_host_ed25519_key";
          }
        ];
      };
      users.users.root.openssh.authorizedKeys.keys = [
        (builtins.readFile "${sshKey}/id_ed25519.pub")
      ];

      networking.firewall.enable = false;

      networking.interfaces.eth1.ipv4.addresses = [
        {
          address = "192.168.1.2";
          prefixLength = 24;
        }
      ];
    };

  m1 = self.lib.init pkgs {
    modules = [
      "${pkgs.path}/nixos/modules/testing/test-instrumentation.nix"
      deviceConfig
      ({ lib, ... }: {
        mantle.version = image1Version;
        mantle.partitions.var.size = lib.mkForce "2048M";
      })
    ];
  };

  m2 = self.lib.init pkgs {
    modules = [
      "${pkgs.path}/nixos/modules/testing/test-instrumentation.nix"
      deviceConfig
      ({ lib, ... }: {
        mantle.version = image2Version;
        networking.hostName = "device";
        services.userborn.static = lib.mkForce false;
      })
    ];
  };

  sshKey = pkgs.runCommand "test-ssh-key" { } ''
    mkdir -p $out
    ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -f $out/key
    cp $out/key $out/id_ed25519
    cp $out/key.pub $out/id_ed25519.pub
  '';
in
{
  name = "overlay";

  nodes = {
    device =
      { ... }:
      {
        imports = [ common.bootNodeModule ];

        virtualisation.sharedDirectories.updates = {
          source = "${m2.updatePayload}";
          target = "/var/updates";
        };
      };

    deployer =
      { ... }:
      {
        nix.enable = true;
        nix.settings.experimental-features = [ "nix-command" ];

        environment.systemPackages = [
          m2.deploy-overlay
          pkgs.openssh
        ];

        environment.etc."ssh/id_ed25519" = {
          source = "${sshKey}/id_ed25519";
          mode = "0600";
        };
        programs.ssh.extraConfig = ''
          IdentityFile /etc/ssh/id_ed25519
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
        '';
      };
  };

  testScript =
    _:
    # python
    ''
      import json

      ${common.diskBoot m1.fullImage "device"}

      device.start(allow_reboot=True)
      device.wait_for_unit("multi-user.target")

      # Clear this because we don't want to attach device's disk for deployer
      del os.environ['NIX_DISK_IMAGE']

      deployer.start()
      deployer.wait_for_unit("multi-user.target")

      with subtest("device boots v1"):
        os_release = device.succeed("cat /etc/os-release")
        t.assertIn('IMAGE_ID="${imageName}"', os_release)
        t.assertIn('IMAGE_VERSION=${image1Version}', os_release)

        device.succeed("systemctl start check-clear-store-upper")
        device.succeed("cmp -s /var/nix/prev-os-release /etc/os-release")

      with subtest("overlay is deactivated on boot (verity bind, not overlay)"):
        fstype = device.succeed("findmnt -n -o FSTYPE -T /nix/store | tail -n1").strip()
        assert fstype != "overlay", f"/nix/store unexpectedly overlay on boot: {fstype}"

      with subtest("overlay activation mounts /nix/store overlay"):
        device.fail("touch /nix/store/.test-file")

        device.succeed("systemctl start nix-store-overlay")
        fstype = device.succeed("findmnt -n -o FSTYPE -T /nix/store | tail -n1").strip()
        assert fstype == "overlay", f"/nix/store is {fstype} after activation"

        device.succeed("touch /nix/store/.test-file")

        device.succeed("systemctl stop nix-store-overlay")
        fstype = device.succeed("findmnt -n -o FSTYPE -T /nix/store | tail -n1").strip()
        assert fstype != "overlay", f"/nix/store still overlay after deactivation: {fstype}"

        device.fail("test -e /nix/store/.test-file")
        device.succeed("test -e /var/nix/upper/nix/store/.test-file")

      with subtest("deploy-overlay switches the device to v2"):
        out = deployer.succeed("deploy-overlay root@device")
        print(out)

        current = device.succeed("readlink /run/current-system").strip()
        assert current == "${m2.overlayToplevel}"

        booted_release = device.succeed("cat /run/booted-system/etc/os-release")
        t.assertIn('IMAGE_VERSION=${image1Version}', booted_release)
        switched_release = device.succeed("cat /etc/os-release")
        t.assertIn('IMAGE_VERSION="${image2Version}~overlay"', switched_release)

      with subtest("overlay upper clears on an A/B update + reboot"):
        device.succeed("test -e /var/nix/upper/nix/store/.test-file")

        device.succeed("cmp -s /var/nix/prev-os-release /run/booted-system/etc/os-release")

        device.succeed(
          "mount -t 9p -o trans=virtio,version=9p2000.L,ro updates /var/updates"
        )
        listing = device.succeed("ls -l /var/updates")
        assert "store" in listing and ".raw.zst" in listing, listing

        before = json.loads(device.succeed("systemd-sysupdate list --json=short"))
        t.assertIn("${image2Version}", before["all"], before)
        t.assertEqual(before["current"], "${image1Version}", before)

        device.succeed("systemd-sysupdate update")

        after = json.loads(device.succeed("systemd-sysupdate list --json=short"))
        t.assertEqual(after["current"], "${image2Version}", after)

        device.succeed("systemd-sysupdate pending")

        device.reboot()
        device.wait_for_unit("multi-user.target")

        os_release = device.succeed("cat /etc/os-release")
        t.assertIn('IMAGE_ID="${imageName}"', os_release)
        t.assertIn('IMAGE_VERSION=${image2Version}', os_release)

        device.succeed("systemctl start check-clear-store-upper")

        device.fail("test -e /var/nix/upper/nix/store/.test-file")

        device.succeed("test -f /var/nix/prev-os-release")
        device.succeed("cmp -s /var/nix/prev-os-release /etc/os-release")
    '';
}
