{ pkgs }:
let
  app = pkgs.writeShellApplication {
    name = "cage-session-app";
    runtimeInputs = [ pkgs.coreutils pkgs.wayvnc ];
    text = builtins.readFile ../../../../scripts/cage-session-app.sh;
  };
in pkgs.writeShellApplication {
  name = "cage-session";
  runtimeInputs = [ pkgs.coreutils pkgs.systemd pkgs.dbus pkgs.cage app ];
  text = builtins.readFile ../../../../scripts/cage-session.sh;
}
