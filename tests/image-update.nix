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
  name = "image-update";

  nodes.machine =
    { ... }:
    {
      imports = [ common.bootNodeModule ];

      virtualisation.sharedDirectories.updates = {
        source = "${m2.updatePayload}";
        target = "/var/updates";
      };
    };

  testScript =
    _:
    # python
    ''
      import json

      ${common.diskBoot m1.fullImage "machine"}

      machine.start(allow_reboot=True)
      machine.wait_for_unit("multi-user.target")

      with subtest("dm-verity protects /nix/store"):
        verity_info = machine.succeed("dmsetup info --target verity usr")
        assert "ACTIVE" in verity_info, f"verity not ACTIVE: {verity_info}"

        backing = machine.succeed("df --output=source /nix/store | tail -n1").strip()
        assert "/dev/mapper/usr" == backing, f"unexpected backing: {backing}"

      with subtest("/nix/store is a read-only bind from /usr/nix/store"):
        opts = machine.succeed("findmnt --first-only --noheadings --output OPTIONS /nix/store").strip()
        assert "ro" in opts.split(","), f"/nix/store not ro: {opts}"

      with subtest("nixos-init populated the rootfs"):
        booted = machine.succeed("readlink /run/booted-system").strip()
        current = machine.succeed("readlink /run/current-system").strip()
        assert booted == "${m1.fullToplevel}", \
          f"booted-system mismatch: {booted}"
        assert current == booted, f"current-system != booted-system: {current} != {booted}"

        sd_analyze = machine.succeed("systemd-analyze")
        assert "(initrd)" in sd_analyze, "systemd-analyze has no initrd info"

      with subtest("/etc/os-release contains v1 image metadata"):
        os_release = machine.succeed("cat /etc/os-release")
        t.assertIn('IMAGE_ID="${imageName}"', os_release)
        t.assertIn('IMAGE_VERSION=${image1Version}', os_release)

      with subtest("bootctl is BLS Type #2"):
        entries = json.loads(machine.succeed("bootctl list --json=short"))
        ukis = [e for e in entries if e["type"] == "type2"]
        t.assertEqual(len(ukis), 1, f"expected one Type #2 UKI, got: {ukis}")

        e = ukis[0]
        t.assertEqual(e["source"], "esp", f"not from ESP: {e}")
        t.assertEqual(e["id"].split("+", 1)[0], "${imageName}_${image1Version}.efi", f"unexpected id: {e}")
        t.assertEqual(e["version"], '${image1Version}', f"v1 version mismatch: {e}")
        t.assertTrue(e["isDefault"], f"v1 should be default: {e}")

      with subtest("stage v2 update payload"):
        machine.succeed("mkdir -p /var/updates")
        machine.succeed(
          "mount -t 9p -o trans=virtio,version=9p2000.L,ro updates /var/updates"
        )
        listing = machine.succeed("ls -l /var/updates")
        assert "store" in listing and ".raw.zst" in listing, listing

      with subtest("systemd-sysupdate applies v2 to slot B"):
        before = json.loads(machine.succeed("systemd-sysupdate list --json=short"))
        t.assertIn("${image1Version}", before["all"], before)
        t.assertIn("${image2Version}", before["all"], before)
        t.assertEqual(before["current"], "${image1Version}", before)

        machine.succeed("systemd-sysupdate update")

        after = json.loads(machine.succeed("systemd-sysupdate list --json=short"))
        t.assertEqual(after["current"], "${image2Version}", after)

        machine.succeed("systemd-sysupdate pending")

      with subtest("both v1 and v2 are discoverable by bootctl"):
        entries = json.loads(machine.succeed("bootctl list --json=short"))
        ukis = [e for e in entries if e["type"] == "type2"]
        ids = {e["id"].split("+", 1)[0] for e in ukis}
        t.assertEqual(
          ids,
          {"${imageName}_${image1Version}.efi", "${imageName}_${image2Version}.efi"},
          f"unexpected UKI set: {ukis}",
        )

      with subtest("device reboots into v2"):
        machine.reboot()
        machine.wait_for_unit("multi-user.target")

      with subtest("/etc/os-release contains v2 image metadata"):
        os_release = machine.succeed("cat /etc/os-release")
        t.assertIn('IMAGE_ID="${imageName}"', os_release)
        t.assertIn('IMAGE_VERSION=${image2Version}', os_release)

      with subtest("bootctl shows v2 active after reboot"):
        entries = json.loads(machine.succeed("bootctl list --json=short"))
        ukis = [e for e in entries if e["type"] == "type2"]
        t.assertEqual(len(ukis), 2, f"v2 UKI not found: {ukis}")
        e = ukis[0]

        t.assertEqual(e["source"], "esp", f"not from ESP: {e}")
        t.assertEqual(e["id"].split("+", 1)[0], "${imageName}_${image2Version}.efi", f"unexpected id: {e}")
        t.assertEqual(e["version"], '${image2Version}', f"v1 version mismatch: {e}")
        t.assertTrue(e["isDefault"], f"v2 should be default: {e}")
        t.assertTrue(e["isSelected"], f"v2 should be selected: {e}")
    '';
}
