# An interactive installer command that uses `systemd-repart` to copy the
# provided partitions to a user-specified target.
{
  lib,
  pkgs,
  utils,
  format ? pkgs.formats.ini { listsAsDuplicateKeys = true; },
}:
name: partitions:
let
  repartCfg = utils.systemdUtils.lib.definitions "repart.d" format (
    lib.mapAttrs (_name: value: { Partition = value.repartConfig; }) partitions
  );
  repartDefs = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (filename: _v: ''
      cat >"$defs/${filename}.conf" <<EOF
      ${builtins.readFile "${repartCfg}/${filename}.conf"}
      EOF
    '') partitions
  );
  # repart installer filesystem detection copied from repart-image.nix
  fileSystems = lib.filter (f: f != null) (
    lib.mapAttrsToList (_n: v: v.repartConfig.Format or null) partitions
  );
  fileSystemToolMapping = {
    "vfat" = [
      pkgs.dosfstools
      pkgs.mtools
    ];
    "ext4" = [ pkgs.e2fsprogs.bin ];
    "squashfs" = [ pkgs.squashfsTools ];
    "erofs" = [ pkgs.erofs-utils ];
    "btrfs" = [ pkgs.btrfs-progs ];
    "xfs" = [ pkgs.xfsprogs ];
    "swap" = [ pkgs.util-linux ];
  };
  fileSystemTools = builtins.concatMap (f: fileSystemToolMapping."${f}") fileSystems;

in
pkgs.writeShellApplication {
  inherit name;

  runtimeInputs = [
    pkgs.systemd
    pkgs.util-linux
  ]
  ++ fileSystemTools;

  text = ''
      opt_assume_yes=

      usage() {
        cat <<USAGE
    usage: ${name} [-y|--yes] <target-disk>

      -y, --yes   Assume "yes" to the confirmation prompt and run
                  non-interactively. Useful for automated/offline installs.
    USAGE
      }

      while [ $# -gt 0 ]; do
        case "$1" in
          -y|--yes)
            opt_assume_yes=1
            shift
            ;;
          -h|--help)
            usage
            exit 0
            ;;
          --)
            shift
            break
            ;;
          -*)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
          *)
            break
            ;;
        esac
      done

      if [ $# -ne 1 ]; then
        usage >&2
        exit 2
      fi
      target="$1"

      if [ ! -b "$target" ]; then
        echo "$target is not a block device" >&2
        exit 2
      fi

      if [ -z "$opt_assume_yes" ]; then
        echo "About to install to $target."
        printf "This will erase all data on %s. Continue? [y/N] " "$target"
        read -r answer

        case "$answer" in
          y|Y|yes|YES)
            ;;
          *)
            echo "Aborted"
            exit 1
            ;;
        esac
      else
        echo "About to install to $target (--yes, skipping confirmation)."
      fi

      defs=$(mktemp -d)
      trap 'rm -rf "$defs"' EXIT

      ${repartDefs}

      systemd-repart \
        --definitions="$defs" \
        --empty=force \
        --dry-run=no \
        "$target"
  '';
}
