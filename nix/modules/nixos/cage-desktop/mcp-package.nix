{ pkgs }:
let
  python = pkgs.python3.withPackages (p: [ p.mcp p.pillow ]);
in pkgs.writeShellApplication {
  name = "cage-mcp";
  runtimeInputs = [
    (import ./package.nix { inherit pkgs; })
    pkgs.grim pkgs.wtype pkgs.python3Packages.vncdotool pkgs.systemd
  ];
  text = ''
    exec ${python}/bin/python3 ${../../../../scripts/cage_mcp.py} "$@"
  '';
}
