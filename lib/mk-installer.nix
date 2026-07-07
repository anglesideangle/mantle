# Self-contained installer command factory.
#
# Builds a shell script (`name`) that writes the given `partitions`' repart
# definitions to a temp dir and runs `systemd-repart --empty=force` against a
# target disk, copying/extending partitions as declared.
#
# The resulting script has no closure dependency: the repart definitions are
# inlined into the script via heredocs, so it can be shipped on its own
# partition and 1:1 copied (e.g. with `CopyBlocks=auto`) onto an installer
# image, or run directly from a build host to flash a target disk.
#
# Each partition in `partitions` is an attrset with a `repartConfig` attribute
# (an attrset of repart.d settings). The attrset KEY becomes the on-disk
# definition filename, so it controls partition ordering (systemd-repart sorts
# definition files by name — use `00-`/`10-`/... prefixes to fix the GPT order).
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
      cat <<'REPART_CONF_EOF' "$defs/${filename}.conf"
      ${builtins.readFile "${repartCfg}/${filename}.conf"}
      REPART_CONF_EOF
    '') partitions
  );
in
pkgs.writeShellScriptBin name ''
  set -euo pipefail

  target="''${1:?usage: ${name} <target-disk>}"

  if [ ! -b "$target" ]; then
    echo "$target is not a block device" >&2
    exit 2
  fi

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

  defs=$(mktemp -d)
  trap 'rm -rf "$defs"' EXIT

  ${repartDefs}

  systemd-repart \
    --definitions="$defs" \
    --empty=force \
    --dry-run=no \
    "$target"
''