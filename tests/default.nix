{ pkgs, modules }:
let
  lib = pkgs.lib;
  allFiles = builtins.readDir ./.;

  testFiles = lib.filterAttrs (
    name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
  ) allFiles;

  stripSuffix = name: lib.removeSuffix ".nix" name;
  tests = lib.mapAttrs' (name: type: {
    name = stripSuffix name;
    value = pkgs.testers.runNixOSTest {
      imports = [ (import ./${name}) ];

      defaults = {
        imports = modules;
      };
    };
  }) testFiles;
in
pkgs.symlinkJoin {
  name = "mantle-tests";
  paths = lib.attrValues tests;
  passthru.tests = tests;
}
