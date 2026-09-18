{config, lib, pkgs, ...}: let
  home = config.home.homeDirectory;
  helper = ../../../../scripts/prepare-iris-routing.py;
  codexHelper = ../../../../scripts/reconcile-codex-config.py;
  codexBaseline = ./codex-managed.toml;
  codexKeybindings = ./codex-keybindings.json;
  codexPython = pkgs.python3.withPackages (pythonPackages: [pythonPackages.tomlkit]);
  codexConfig = pkgs.writeShellApplication {
    name = "codex-config";
    runtimeInputs = [codexPython];
    text = ''
      exec python3 ${codexHelper} "$@"
    '';
  };
  command = mode: ''
    run ${pkgs.python3}/bin/python3 ${helper} ${mode} ${lib.escapeShellArg home} \
      --git ${pkgs.git}/bin/git
  '';
in {
  home.packages = [codexConfig];

  # Preserve legacy skill-local config before replacing a Stow generation,
  # then expose the private config beside skills at ~/.agents/config/iris.
  home.activation.migrateIrisRouting = lib.hm.dag.entryBetween ["stowDotfiles"] ["writeBoundary"] (command "migrate");
  home.activation.linkIrisRouting = lib.hm.dag.entryAfter ["stowDotfiles"] (command "link");

  # Overlay only the explicitly tracked leaves. Everything else remains owned
  # by Codex, including project trust and application-generated state.
  home.activation.reconcileCodexConfiguration = lib.hm.dag.entryAfter ["writeBoundary" "stowDotfiles"] ''
    run ${codexConfig}/bin/codex-config apply \
      --baseline ${codexBaseline} \
      --keybindings-manifest ${codexKeybindings} \
      --config ${lib.escapeShellArg "${home}/.codex/config.toml"} \
      --keybindings ${lib.escapeShellArg "${home}/.codex/keybindings.json"}
  '';
}
