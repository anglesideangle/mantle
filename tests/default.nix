{ pkgs, modules }:

let
  lib = pkgs.lib;
  allFiles = builtins.readDir ./.;

  testFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) allFiles;

  stripSuffix = name: lib.removeSuffix ".nix" name;
in
lib.mapAttrs' (name: type: {
  name = stripSuffix name;
  value = pkgs.testers.runNixOSTest {
    imports = [ (import ./${name}) ];

    defaults = {
      imports = modules;
    };
  };
}) testFiles
