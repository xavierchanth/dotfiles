{ config, jioPackageFor, lib, pkgs, ... }: let
  cfg = config.dotfiles.jio;
  toml = pkgs.formats.toml {};
  personal = kind: provider: { inherit kind provider; account_group = "personal"; };
  package = jioPackageFor pkgs;
  configDir = "${config.xdg.configHome}/jio";
  dataDir = "${config.xdg.dataHome}/jio";
  stateDir = "${config.xdg.stateHome}/jio";
  runtimeDir = "${stateDir}/runtime";
  command = pkgs.writeShellApplication {
    name = "jio";
    runtimeInputs = [ pkgs.git pkgs.gh pkgs.openssh ];
    text = ''
      export XDG_CACHE_HOME=${lib.escapeShellArg config.xdg.cacheHome}
      export PATH=${lib.escapeShellArg "${config.home.homeDirectory}/.local/share/mise/shims"}:"$PATH"
      exec ${package}/bin/jio \
        --config-dir ${lib.escapeShellArg configDir} \
        --data-dir ${lib.escapeShellArg dataDir} \
        --state-dir ${lib.escapeShellArg stateDir} \
        --runtime-dir ${lib.escapeShellArg runtimeDir} "$@"
    '';
  };
in {
  options.dotfiles.jio = {
    settings = lib.mkOption {
      type = toml.type;
      default = {
        schema_version = 1;
        signing = { policy = "required"; format = "ssh-ed25519"; };
        adapters.enabled = [ "codex-app-server" ];
        profiles = {
          codex = personal "runtime" "openai" // { adapter = "codex-app-server"; };
          github = personal "repository" "github";
          github-signing = personal "signing" "github";
        };
      };
      description = "Portable Jio configuration; account bindings and credentials remain local.";
    };
    projects = lib.mkOption {
      type = lib.types.listOf toml.type;
      default = [];
      description = "Portable Jio project declarations, without credentials or local checkout paths.";
    };
    command = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = command;
      description = "Jio command with identical directory selection for shell and service use.";
    };
  };
  config = {
    home.packages = [ (lib.hiPrio command) package pkgs.gh pkgs.python3 ];
    xdg.configFile."jio/config.toml".source = toml.generate "jio-config.toml" cfg.settings;
    xdg.configFile."jio/projects.toml".source = toml.generate "jio-projects.toml" {
      schema_version = 1;
      projects = cfg.projects;
    };
  };
}
