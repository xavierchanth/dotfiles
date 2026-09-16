{config, lib, pkgs, ...}: let
  home = config.home.homeDirectory;
  helper = ../../../../scripts/prepare-iris-routing.py;
  run = mode: ''
    ${pkgs.python3}/bin/python3 ${helper} ${mode} ${lib.escapeShellArg home} \
      --git ${pkgs.git}/bin/git
  '';
in {
  # Capture routing files from the current Stow generation before a managed
  # deployment replaces it, then restore stable links after Stow activation.
  home.activation.migrateIrisRouting = lib.hm.dag.entryBefore ["stowDotfiles"] (run "migrate");
  home.activation.linkIrisRouting = lib.hm.dag.entryAfter ["stowDotfiles"] (run "link");
}
