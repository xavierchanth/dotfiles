{
  config,
  lib,
  pkgs,
  ...
}: let
  keyDir = "${config.home.homeDirectory}/.config/cli-proxy-api";
  brewPrefix = if pkgs.stdenv.hostPlatform.isAarch64 then "/opt/homebrew" else "/usr/local";
  confPath = "${brewPrefix}/etc/cliproxyapi.conf";

  # Models served through OpenCode Zen (pay-per-token). gpt-* and claude-* are
  # deliberately absent: gpt-* names must route to the Codex OAuth account, and
  # Claude models stay on the subscription via plain `claude`.
  zenModels = [
    "kimi-k3"
    "glm-5.2"
    "grok-4.5"

  ];

  # Indentation is baked in because interpolations into '' strings are inserted
  # verbatim; these lines must sit under openai-compatibility[0].models.
  zenModelYaml = lib.concatMapStrings (m: "      - name: \"${m}\"\n        alias: \"${m}\"\n") zenModels;

  # @LOCAL_KEY@ / @MGMT_KEY@ / @ZEN_KEY@ are spliced in at activation from
  # untracked files under ~/.config/cli-proxy-api so no secret enters the store.
  confTemplate = pkgs.writeText "cliproxyapi.conf.in" ''
    host: "127.0.0.1"
    port: 8317

    remote-management:
      allow-remote: false
      secret-key: @MGMT_KEY@

    auth-dir: "~/.cli-proxy-api"

    api-keys:
      - @LOCAL_KEY@

    # CPA-Manager-Plus reads the usage queue for request history/cost analytics.
    usage-statistics-enabled: true
    redis-usage-queue-retention-seconds: 3600

    request-retry: 3

    openai-compatibility:
      - name: "opencode-zen"
        base-url: "https://opencode.ai/zen/v1"
        api-key-entries:
          - api-key: @ZEN_KEY@
        models:
    ${zenModelYaml}'';

  cpampVersion = "1.11.7";
  cpampArtifact =
    if pkgs.stdenv.hostPlatform.system == "aarch64-darwin" then {
      name = "cpa-manager-plus_v${cpampVersion}_darwin_arm64";
      sha256 = "61e895a357eea749588c203ff2ce6483bdafa45b52afaf4c452caf75960ddc33";
    }
    else throw "CPA Manager Plus is unsupported on ${pkgs.stdenv.hostPlatform.system}";
  cpampTarball = pkgs.fetchurl {
    url = "https://github.com/seakee/CPA-Manager-Plus/releases/download/v${cpampVersion}/${cpampArtifact.name}.tar.gz";
    inherit (cpampArtifact) sha256;
  };

  # CPAMP writes its data/ directory next to its own binary, so it cannot run
  # from the read-only store; activation installs it into this dir instead.
  cpampHome = "${config.home.homeDirectory}/.local/share/cpa-manager-plus";

  ccx = pkgs.writeShellApplication {
    name = "ccx";
    text = ''
      key_file="${keyDir}/local.key"
      if [ ! -f "$key_file" ]; then
        echo "ccx: ${keyDir}/local.key missing; run a home-manager switch first" >&2
        exit 1
      fi
      exec env \
        ANTHROPIC_BASE_URL="http://127.0.0.1:8317" \
        ANTHROPIC_AUTH_TOKEN="$(cat "$key_file")" \
        ANTHROPIC_MODEL="''${CCX_MODEL:-gpt-5.6-sol}" \
        ANTHROPIC_SMALL_FAST_MODEL="''${CCX_SMALL_MODEL:-gpt-5.6-luna}" \
        CLAUDE_CODE_EFFORT_LEVEL="''${CCX_EFFORT:-low}" \
        claude "$@"
    '';
  };
in {
  home.packages = [ccx];

  home.activation.cliProxyApi = lib.hm.dag.entryAfter ["writeBoundary"] ''
    key_dir="${keyDir}"
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"

    # Local API key (what ccx presents) and management-UI key: generated once,
    # never stored in the repo.
    for key in local.key management.key; do
      if [ ! -s "$key_dir/$key" ]; then
        /usr/bin/od -An -tx1 -N24 /dev/urandom | tr -d ' \n' >"$key_dir/$key"
        chmod 600 "$key_dir/$key"
      fi
    done

    if [ ! -s "$key_dir/zen.key" ]; then
      echo "cliproxy.nix: put your OpenCode Zen API key in $key_dir/zen.key (Zen models will 401 until then)" >&2
    fi

    conf="${confPath}"
    if [ -d "$(dirname "$conf")" ]; then
      tmp="$(mktemp)"
      # JSON strings are valid YAML scalars. Python reads secrets directly from
      # files, avoiding shell and sed interpolation entirely (including newlines).
      ${pkgs.python3}/bin/python3 - ${confTemplate} "$key_dir/local.key" \
        "$key_dir/management.key" "$key_dir/zen.key" "$tmp" <<'PY'
import json, pathlib, sys
source, local, management, zen, output = map(pathlib.Path, sys.argv[1:])
# Key files are conventionally newline-terminated. Remove only trailing line
# endings; spaces and every other character are part of the key.
def read_key(path):
    return path.read_text().rstrip("\r\n")

values = {
    "@LOCAL_KEY@": read_key(local),
    "@MGMT_KEY@": read_key(management),
    "@ZEN_KEY@": read_key(zen) if zen.exists() and zen.stat().st_size else "MISSING-ZEN-KEY",
}
text = source.read_text()
for marker, value in values.items():
    text = text.replace(marker, json.dumps(value))
output.write_text(text)
PY
      if ! /usr/bin/cmp -s "$tmp" "$conf"; then
        mv "$tmp" "$conf"
        # Restart the brew service so the new config is picked up; harmless if
        # the service isn't loaded yet (first install).
        /bin/launchctl kickstart -k "gui/$(id -u)/homebrew.mxcl.cliproxyapi" 2>/dev/null || true
      else
        rm -f "$tmp"
      fi
    else
      echo "cliproxy.nix: ${confPath} parent missing; is homebrew's cliproxyapi installed?" >&2
    fi
  '';

  home.activation.cpaManagerPlus = lib.hm.dag.entryAfter ["writeBoundary"] ''
    cpamp_home="${cpampHome}"
    mkdir -p "$cpamp_home"
    if [ ! -f "$cpamp_home/.version" ] || [ "$(cat "$cpamp_home/.version")" != "${cpampVersion}" ]; then
      tmp_dir="$(mktemp -d)"
      /usr/bin/tar -xzf ${cpampTarball} -C "$tmp_dir"
      install -m 755 "$tmp_dir/${cpampArtifact.name}/cpa-manager-plus" \
        "$cpamp_home/cpa-manager-plus"
      rm -rf "$tmp_dir"
      echo "${cpampVersion}" >"$cpamp_home/.version"
      /bin/launchctl kickstart -k "gui/$(id -u)/cpa-manager-plus" 2>/dev/null || true
    fi
  '';

  launchd.agents.cpa-manager-plus = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      ProgramArguments = ["${cpampHome}/cpa-manager-plus"];
      WorkingDirectory = cpampHome;
      RunAtLoad = true;
      KeepAlive = true;
      # First run prints the CPAMP admin key here; retrieve it with:
      #   grep "admin key" ~/.local/share/cpa-manager-plus/cpamp.log
      StandardOutPath = "${cpampHome}/cpamp.log";
      StandardErrorPath = "${cpampHome}/cpamp.log";
      ProcessType = "Background";
    };
  };
}
