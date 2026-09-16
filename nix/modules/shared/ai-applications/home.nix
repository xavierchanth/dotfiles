{config, lib, pkgs, ...}: let
  home = config.home.homeDirectory;
  helper = ../../../../scripts/prepare-iris-routing.py;
  command = mode: ''
    run ${pkgs.python3}/bin/python3 ${helper} ${mode} ${lib.escapeShellArg home} \
      --git ${pkgs.git}/bin/git
  '';
in {
  # Preserve legacy skill-local config before replacing a Stow generation,
  # then expose the private config beside skills at ~/.agents/config/iris.
  home.activation.migrateIrisRouting = lib.hm.dag.entryBetween ["stowDotfiles"] ["writeBoundary"] (command "migrate");
  home.activation.linkIrisRouting = lib.hm.dag.entryAfter ["stowDotfiles"] (command "link");
}
