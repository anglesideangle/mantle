{
  pkgs,
  self,
}:
let
  common = import ./common.nix { inherit pkgs; };

  imageName = "mantle-test";
  image1Version = "1";
  image2Version = "2";

  deviceConfig = {
    nixpkgs = { inherit (pkgs.stdenv) hostPlatform buildPlatform; };

    boot.loader.systemd-boot.enable = true;

    boot.initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_blk"
    ];

    mantle = {
      enable = true;
      name = imageName;
      partitions = {
        esp.size = "64M";
        store.size = "1024M";
        store-verity.size = "64M";
        var.size = "128M";
      };
    };
  };

  m1 = self.lib.init pkgs {
    modules = [
      "${pkgs.path}/nixos/modules/testing/test-instrumentation.nix"
      deviceConfig
      { mantle.version = image1Version; }
    ];
  };

  m2 = self.lib.init pkgs {
    modules = [
      "${pkgs.path}/nixos/modules/testing/test-instrumentation.nix"
      deviceConfig
      { mantle.version = image2Version; }
    ];
  };
in
{
  name = "installer";

  nodes = {
    deployer =
      { ... }:
      {
        environment.systemPackages = [
          m1.flash-to-device
          pkgs.systemd
        ];
        virtualisation.emptyDiskImages = [ 3072 ];
      };

    installed =
      { ... }:
      {
        imports = [ common.bootNodeModule ];

        virtualisation.sharedDirectories.updates = {
          source = "${m2.updatePayload}";
          target = "/var/updates";
        };
      };
  };

  testScript =
    _:
    # python
    ''
      import json
      import os
      import shutil

      deployer.start()
      deployer.wait_for_unit("multi-user.target")

      with subtest("flash-to-device writes the image to /dev/vdb"):
        out = deployer.succeed("flash-to-device -y /dev/vdb")
        print(out)

      with subtest("target disk has the expected partitions"):
        blkid = deployer.succeed("blkid /dev/vdb*")
        print(blkid)
        assert "LABEL=\"store_1\"" in blkid, "store_1 partition missing"
        assert "LABEL=\"boot\"" in blkid, "ESP (boot) missing"
        assert "LABEL=\"persistent\"" in blkid, "var (persistent) missing"

        gpt = deployer.succeed("sfdisk -d /dev/vdb")
        print(gpt)
        for label in ["boot", "store_1", "store-verity_1", "persistent", "_empty"]:
          assert f'name="{label}"' in gpt, f"{label} partition missing: {gpt}"

      with subtest("ESP contains the UKI"):
        deployer.succeed("mkdir -p /mnt/esp && mount /dev/vdb1 /mnt/esp")
        uki_listing = deployer.succeed("find /mnt/esp -name '*.efi' -ls")
        print(uki_listing)
        assert "${imageName}_${image1Version}+2.efi" in uki_listing, uki_listing
        deployer.succeed("umount /mnt/esp")

      with subtest("installed system boots from the written disk"):
        deployer.shutdown()

        src = str(deployer.state_dir / "empty0.qcow2")
        dst = str(installed.state_dir / "installed-disk.qcow2")
        shutil.copy2(src, dst)
        os.environ['NIX_DISK_IMAGE'] = dst

        installed.start(allow_reboot=True)
        installed.wait_for_unit("multi-user.target")

        os_release = installed.succeed("cat /etc/os-release")
        t.assertIn('IMAGE_ID="${imageName}"', os_release)
        t.assertIn('IMAGE_VERSION=${image1Version}', os_release)

      with subtest("dm-verity protects /nix/store on the installed system"):
        verity_info = installed.succeed("dmsetup info --target verity usr")
        assert "ACTIVE" in verity_info, verity_info

      with subtest("installed system takes an A/B update to v2"):
        installed.succeed("mkdir -p /var/updates")
        installed.succeed(
          "mount -t 9p -o trans=virtio,version=9p2000.L,ro updates /var/updates"
        )
        listing = installed.succeed("ls -l /var/updates")
        assert "store" in listing and ".raw.zst" in listing, listing

        before = json.loads(installed.succeed("systemd-sysupdate list --json=short"))
        t.assertIn("${image2Version}", before["all"], before)
        t.assertEqual(before["current"], "${image1Version}", before)

        installed.succeed("systemd-sysupdate update")

        after = json.loads(installed.succeed("systemd-sysupdate list --json=short"))
        t.assertEqual(after["current"], "${image2Version}", after)

        installed.succeed("systemd-sysupdate pending")

        installed.reboot()
        installed.wait_for_unit("multi-user.target")

        os_release = installed.succeed("cat /etc/os-release")
        t.assertIn('IMAGE_ID="${imageName}"', os_release)
        t.assertIn('IMAGE_VERSION=${image2Version}', os_release)
    '';
}
