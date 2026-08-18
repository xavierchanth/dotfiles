{
  config,
  lib,
  pkgs,
  ...
}: let
  settingsPath = "${config.home.homeDirectory}/.claude/settings.json";

  # Repo-owned settings. Claude Code also writes this file itself (/config, /model,
  # /theme), so these keys are merged over whatever is on disk rather than
  # replacing it. Anything not listed here is left alone.
  #
  # defaultMode "auto" is only honored from user, policy, or --settings sources;
  # Claude ignores it in project or local settings on purpose, so it has to live
  # in ~/.claude/settings.json.
  managedSettings = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    includeCoAuthoredBy = false;
    model = "opus";
    permissions.defaultMode = "auto";
    disableRemoteControl = true;
    autoMemoryEnabled = false;
    remoteControlAtStartup = false;
    env = {
      CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
      DISABLE_ERROR_REPORTING = "1";
    };
    sandbox = {
      enabled = true;
      autoAllowBashIfSandboxed = true;
    };
  };

  managedSettingsFile = pkgs.writeText "claude-managed-settings.json" (builtins.toJSON managedSettings);

  # Claude's own "auto" theme resolves only to the plain `light`/`dark` themes,
  # with no way to reach the ANSI variants, so drive them from macOS appearance
  # instead. Claude polls settings.json with fs.watchFile, so a write here is
  # picked up by running sessions without a restart.
  themeSync = pkgs.writeShellApplication {
    name = "claude-theme-sync";
    runtimeInputs = [pkgs.jq pkgs.coreutils];
    text = ''
      settings="${settingsPath}"
      [ -f "$settings" ] || exit 0

      # Absolute path: launchd agents start with a minimal PATH.
      if [ "$(/usr/bin/defaults read -g AppleInterfaceStyle 2>/dev/null || true)" = "Dark" ]; then
        want="dark-ansi"
      else
        want="light-ansi"
      fi

      current="$(jq -r '.theme // ""' "$settings" 2>/dev/null || true)"
      [ "$current" = "$want" ] && exit 0

      # Temp file alongside the target so the rename is atomic; Claude polls this
      # file and must never observe a partial write.
      tmp="$(mktemp "$settings.XXXXXX")"
      trap 'rm -f "$tmp"' EXIT
      jq --arg theme "$want" '.theme = $theme' "$settings" >"$tmp"
      mv "$tmp" "$settings"
      trap - EXIT
    '';
  };
in {
  home.packages = lib.optionals pkgs.stdenv.isDarwin [themeSync];

  home.activation.claudeSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    settings="${settingsPath}"
    mkdir -p "$(dirname "$settings")"
    [ -f "$settings" ] || echo '{}' >"$settings"

    # Recursive merge, managed keys winning, so editing this module takes effect
    # while preserving keys Claude wrote for itself (model, effortLevel, tui, ...).
    # Remove settings that this module previously managed but intentionally retired.
    tmp="$(mktemp "$settings.XXXXXX")"
    if ${pkgs.jq}/bin/jq -s \
      '(.[0] | del(
        .permissions.deny,
        .disableAgentView,
        .disableAllHooks,
        .disableArtifact,
        .disableClaudeAiConnectors,
        .disableWorkflows,
        .agentPushNotifEnabled,
        .autoUploadSessions,
        .inputNeededNotifEnabled,
        .env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC,
        .env.CLAUDE_CODE_SKIP_PLUGIN_MCP_SERVERS,
        .env.DISABLE_TELEMETRY
      )) * .[1]' \
      "$settings" ${managedSettingsFile} >"$tmp"; then
      mv "$tmp" "$settings"
    else
      rm -f "$tmp"
      echo "claude.nix: could not merge settings into $settings" >&2
    fi

    ${lib.optionalString pkgs.stdenv.isDarwin "${themeSync}/bin/claude-theme-sync || true"}
  '';

  # Claude Code only discovers ~/.claude/skills/<name>/SKILL.md — no recursion,
  # and a symlinked parent directory is not scanned (anthropics/claude-code
  # #18192). So the ~/.agents/skills tree (stowed, category subfolders) is
  # flattened into per-skill symlinks here instead of one directory link.
  home.activation.claudeSkills = lib.hm.dag.entryAfter ["writeBoundary" "stowDotfiles"] ''
    skills_src="${config.home.homeDirectory}/.agents/skills"
    skills_dest="${config.home.homeDirectory}/.claude/skills"
    mkdir -p "$skills_dest"

    # Drop links we created whose target skill no longer exists.
    for link in "$skills_dest"/*; do
      [ -L "$link" ] || continue
      target="$(readlink "$link" || true)"
      case "$target" in
        "$skills_src"/*)
          [ -f "$target/SKILL.md" ] || rm -f "$link"
          ;;
      esac
    done

    [ -d "$skills_src" ] || exit 0
    ${pkgs.findutils}/bin/find -L "$skills_src" -maxdepth 4 -name SKILL.md 2>/dev/null | while read -r skill_md; do
      skill_dir="$(dirname "$skill_md")"
      name="$(basename "$skill_dir")"
      existing="$skills_dest/$name"
      if [ -e "$existing" ] && [ ! -L "$existing" ]; then
        echo "claude.nix: not linking skill '$name'; $existing exists and is not a symlink" >&2
        continue
      fi
      ln -sfn "$skill_dir" "$existing"
    done
  '';

  # WatchPaths catches the appearance toggle as cfprefsd flushes the global
  # preferences; StartInterval is a backstop for when that write is coalesced.
  launchd.agents = lib.optionalAttrs pkgs.stdenv.isDarwin {
    claude-theme-sync = {
      enable = true;
      config = {
        ProgramArguments = ["${themeSync}/bin/claude-theme-sync"];
        RunAtLoad = true;
        StartInterval = 30;
        WatchPaths = ["${config.home.homeDirectory}/Library/Preferences/.GlobalPreferences.plist"];
        ProcessType = "Background";
      };
    };
  };
}
