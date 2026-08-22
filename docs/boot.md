# Boot

The boot process for a linux system consists of several stages:
- bootloader
- stage 1
- stage 2

## The Depths

Before we can get to stages of the boot process that we control, it's important
to recognize that every stage of the process must be triggered by a prior stage.
What this stage is depends on what computer your software is running on. For
example, modern PCs have firmware that implements the UEFI standard, which is
what your bootloader conforms to. On the other hand, Raspberry Pis have firmware
living on a separate EEPROM that loads a kernel or another bootloader on the
main SSD.

Every stage of the boot process must be triggered by a stage before it.

UEFI:

- EFI system partition (ESP) (this is mounted to `/boot` on a booted linux system) formatted as fat32.
  - for an x86_64 system, the bootloader located in `/boot/EFI/BOOT/BOOTX64.EFI`, for an aarch64 system, it's located in `/boot/EFI/BOOT/BOOTA64.EFI`

- uefi is garbage

- systemd-boot and grub work for uefi
  - some systems don't have uefi

- each stage allows for a large subsequent stage (e.g. bootloader is small, loads uki, uki loads full linux system)

## Stage 1 init

- you don't need stage 1 init or an initrd/uki, could just be a static kernel
  - improves boot speed
  - need to compile your own kernel

## Stage 2 init

- your real system is loaded now
