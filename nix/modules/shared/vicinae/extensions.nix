{
  inputs,
  lib,
  pkgs,
}: let
  cleanExtensionSource = source:
    lib.cleanSourceWith {
      src = source;
      filter = path: type: let
        name = baseNameOf path;
      in
        !(builtins.elem name [
          "node_modules"
          "dist"
          "build"
          ".raycast"
          "vicinae-env.d.ts"
        ]);
    };

  mkExtension = name:
    inputs.vicinae.lib.${pkgs.stdenv.hostPlatform.system}.mkVicinaeExtension {
      pname = name;
      version = "0.1.0";
      src = cleanExtensionSource ../../../../packages/vicinae/${name};
    };

in
  mkExtension "window-management"
