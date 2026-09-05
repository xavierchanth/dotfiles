{ config, lib, pkgs, ... }: let
  server = import ./mcp-package.nix { inherit pkgs; };
in {
  home.file.".codex/skills/cage-session/SKILL.md".source = ./skills/cage-session/SKILL.md;
  home.activation.registerCageMcp = lib.hm.dag.entryAfter [ "writeBoundary" "installMiseTools" ] ''
    CODEX_HOME=${lib.escapeShellArg "${config.home.homeDirectory}/.codex"} \
      ${lib.escapeShellArg "${config.home.homeDirectory}/.local/share/mise/shims/codex"} \
      mcp add cage -- ${server}/bin/cage-mcp
  '';
}
