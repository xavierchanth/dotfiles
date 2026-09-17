{
  inputs,
  lib,
  pkgs,
}: let
  source = lib.cleanSourceWith {
    src = ../../../../stow/vicinae-window-management;
    filter = path: type: let
      name = baseNameOf path;
    in !builtins.elem name ["node_modules" "vicinae-env.d.ts"];
  };
in
  inputs.vicinae.lib.${pkgs.stdenv.hostPlatform.system}.mkVicinaeExtension {
    pname = "window-management";
    version = "0.1.0";
    src = source;
  }
