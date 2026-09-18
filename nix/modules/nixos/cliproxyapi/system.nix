{ config, lib, pkgs, ... }:
let
  release = "v7.3.5";
  version = lib.removePrefix "v" release;
  cfg = config.dotfiles.cliproxyapi;
  serviceUser = "cliproxyapi";
  stateDirectory = "/var/lib/cliproxyapi";
  authDirectory = "${stateDirectory}/auth";
  clientKeyDirectory = "${stateDirectory}/client-keys";
  managementKeyFile = "${stateDirectory}/management-key";
  runtimeDirectory = "/run/cliproxyapi";
  runtimeConfig = "${runtimeDirectory}/config.yaml";
  artifacts = {
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-BBUFGj7Y5cZZ7acBfvRddLV0sfR07ogMsrktpEu2H7M=";
    };
    aarch64-linux = {
      arch = "aarch64";
      hash = "sha256-mB1DWkGbtxmFkL1JzC2FMYEEHFgWllxD5iTQX1b2qs0=";
    };
  };
  artifact = artifacts.${pkgs.stdenv.hostPlatform.system}
    or (throw "CLIProxyAPI does not provide a pinned artifact for ${pkgs.stdenv.hostPlatform.system}");
  source = pkgs.fetchurl {
    url = "https://github.com/router-for-me/CLIProxyAPI/releases/download/${release}/CLIProxyAPI_${version}_linux_${artifact.arch}_no-plugin.tar.gz";
    inherit (artifact) hash;
  };
  package = pkgs.stdenvNoCC.mkDerivation {
    pname = "cliproxyapi";
    inherit version;
    src = source;
    sourceRoot = ".";
    installPhase = ''
      runHook preInstall
      install -Dm0555 cli-proxy-api "$out/bin/cli-proxy-api"
      install -Dm0444 LICENSE "$out/share/licenses/cliproxyapi/LICENSE"
      runHook postInstall
    '';
  };
  clientTemplateText = ''
    # Optional Codex adapter for the initial client rollout; the gateway itself
    # is provider- and client-neutral.
    # Supply CLIPROXYAPI_TOKEN at launch from a protected runtime source.
    model_provider = "cliproxyapi"

    [model_providers.cliproxyapi]
    name = "CLIProxyAPI (third-party, unsupported by OpenAI)"
    base_url = "${cfg.canonicalBaseUrl}"
    env_key = "CLIPROXYAPI_TOKEN"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = true
  '';
  prepare = pkgs.writeShellApplication {
    name = "cliproxyapi-prepare";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.openssl ];
    text = ''
      set -euo pipefail
      umask 077
      install -d -m 0700 ${authDirectory} ${clientKeyDirectory} ${runtimeDirectory}

      ensure_secret() {
        destination=$1
        prefix=$2
        bytes=$3
        if [ ! -e "$destination" ]; then
          temporary="$(mktemp "$destination.XXXXXX")"
          trap 'rm -f "$temporary"' EXIT
          printf '%s%s\n' "$prefix" "$(openssl rand -hex "$bytes")" > "$temporary"
          chmod 0600 "$temporary"
          mv "$temporary" "$destination"
          trap - EXIT
        fi
        test -f "$destination" && test ! -L "$destination"
        chmod 0600 "$destination"
      }

      ensure_secret ${clientKeyDirectory}/poseidon cpa_poseidon_ 32
      ensure_secret ${clientKeyDirectory}/zeus cpa_zeus_ 32
      ensure_secret ${managementKeyFile} cpa_management_ ${toString cfg.managementKeyBytes}
      poseidon_token="$(tr -d '\r\n' < ${clientKeyDirectory}/poseidon)"
      zeus_token="$(tr -d '\r\n' < ${clientKeyDirectory}/zeus)"
      management_key="$(tr -d '\r\n' < ${managementKeyFile})"
      if printf '%s\n' "$management_key" | grep -Eq '^cpa_management_[0-9a-f]{64}$'; then
        temporary="$(mktemp ${stateDirectory}/.management-key.XXXXXX)"
        trap 'rm -f "$temporary"' EXIT
        printf '%s\n' "$management_key" | cut -c 1-${toString (15 + (cfg.managementKeyBytes * 2))} > "$temporary"
        chmod 0600 "$temporary"
        mv "$temporary" ${managementKeyFile}
        trap - EXIT
        management_key="$(tr -d '\r\n' < ${managementKeyFile})"
      fi
      printf '%s\n' "$poseidon_token" | grep -Eq '^cpa_poseidon_[0-9a-f]{64}$'
      printf '%s\n' "$zeus_token" | grep -Eq '^cpa_zeus_[0-9a-f]{64}$'
      printf '%s\n' "$management_key" | grep -Eq '^cpa_management_[0-9a-f]{${toString (cfg.managementKeyBytes * 2)}}$'
      test "$(printf '%s' "$management_key" | wc -c)" -le 72
      test "$poseidon_token" != "$zeus_token"

      temporary="$(mktemp ${runtimeDirectory}/.config.XXXXXX)"
      trap 'rm -f "$temporary"' EXIT
      {
        printf '%s\n' \
          'host: "127.0.0.1"' \
          'port: 8317' \
          'tls:' \
          '  enable: false' \
          'remote-management:' \
          '  allow-remote: false' \
          "  secret-key: \"$management_key\"" \
          '  disable-control-panel: true' \
          '  disable-auto-update-panel: true' \
          'auth-dir: "${authDirectory}"' \
          'api-keys:' \
          "  - \"$poseidon_token\"" \
          "  - \"$zeus_token\"" \
          'debug: false' \
          'request-log: false' \
          'logging-to-file: false' \
          'usage-statistics-enabled: false' \
          'pprof:' \
          '  enable: false' \
          'discovery:' \
          '  enabled: false' \
          'plugins:' \
          '  enabled: false' \
          'routing:' \
          '  strategy: "${cfg.routingStrategy}"' \
          '  session-affinity: ${lib.boolToString cfg.sessionAffinity}' \
          '  session-affinity-ttl: "${cfg.sessionAffinityTtl}"' \
          '  session-affinity-subagents: true' \
          'ws-auth: true' \
          'streaming:' \
          '  keepalive-seconds: 15' \
          '  bootstrap-retries: 1'
      } > "$temporary"
      chmod 0600 "$temporary"
      mv "$temporary" ${runtimeConfig}
      trap - EXIT
    '';
  };
  bootstrap = pkgs.writeShellApplication {
    name = "cliproxyapi-provider-bootstrap";
    runtimeInputs = [ pkgs.coreutils pkgs.systemd pkgs.util-linux ];
    text = ''
      set -euo pipefail
      umask 077
      if [ "$(id -u)" -ne 0 ]; then
        echo 'cliproxyapi-provider-bootstrap must run as root' >&2
        exit 1
      fi
      if [ "$#" -ne 1 ]; then
        echo 'usage: cliproxyapi-provider-bootstrap codex-device|codex|claude|antigravity|kimi|xai|devin|meta' >&2
        exit 64
      fi
      case "$1" in
        codex-device) login_flag=-codex-device-login ;;
        codex) login_flag=-codex-login ;;
        claude) login_flag=-claude-login ;;
        antigravity) login_flag=-antigravity-login ;;
        kimi) login_flag=-kimi-login ;;
        xai) login_flag=-xai-login ;;
        devin) login_flag=-devin-login ;;
        meta) login_flag=-meta-login ;;
        *) exit 64 ;;
      esac
      restart=0
      if systemctl is-active --quiet cliproxyapi.service; then
        systemctl stop cliproxyapi.service
        restart=1
      fi
      finish() {
        status=$?
        if [ "$restart" -eq 1 ]; then
          systemctl start cliproxyapi.service || status=1
        fi
        exit "$status"
      }
      trap finish EXIT INT TERM
      install -d -m 0700 -o ${serviceUser} -g ${serviceUser} ${stateDirectory} ${authDirectory} ${clientKeyDirectory} ${runtimeDirectory}
      runuser --user ${serviceUser} -- ${prepare}/bin/cliproxyapi-prepare
      cd ${stateDirectory}
      runuser --user ${serviceUser} -- ${package}/bin/cli-proxy-api \
        -config ${runtimeConfig} "$login_flag" -no-browser
    '';
  };
  clientToken = pkgs.writeShellApplication {
    name = "cliproxyapi-client-token";
    runtimeInputs = [ pkgs.coreutils pkgs.openssl pkgs.systemd ];
    text = ''
      set -euo pipefail
      umask 077
      if [ "$(id -u)" -ne 0 ]; then
        echo 'cliproxyapi-client-token must run as root' >&2
        exit 1
      fi
      if [ "$#" -ne 2 ]; then
        echo 'usage: cliproxyapi-client-token show|rotate poseidon|zeus' >&2
        exit 64
      fi
      action=$1
      case "$2" in poseidon|zeus) client=$2 ;; *) exit 64 ;; esac
      destination="${clientKeyDirectory}/$client"
      case "$action" in
        show)
          test -f "$destination" && test ! -L "$destination"
          sed -n '1p' "$destination"
          ;;
        rotate)
          temporary="$(mktemp "${clientKeyDirectory}/.$client.XXXXXX")"
          trap 'rm -f "$temporary"' EXIT
          printf 'cpa_%s_%s\n' "$client" "$(openssl rand -hex 32)" > "$temporary"
          install -m 0600 -o ${serviceUser} -g ${serviceUser} "$temporary" "$destination"
          rm -f "$temporary"
          trap - EXIT
          systemctl restart cliproxyapi.service
          printf 'rotated %s; retrieve it with the show action\n' "$client"
          ;;
        *) exit 64 ;;
      esac
    '';
  };
  accountControl = pkgs.writeShellApplication {
    name = "cliproxyapi-account";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.gnugrep pkgs.jq ];
    text = ''
      set -euo pipefail
      umask 077
      if [ "$(id -u)" -ne 0 ]; then
        echo 'cliproxyapi-account must run as root' >&2
        exit 1
      fi
      if [ "$#" -lt 1 ]; then
        echo 'usage: cliproxyapi-account status | enable FILE | disable FILE | priority FILE INTEGER | note FILE LABEL | show-management-key' >&2
        exit 64
      fi
      action=$1
      if [ "$action" = show-management-key ]; then
        if [ "$#" -ne 1 ]; then exit 64; fi
        test -f ${managementKeyFile} && test ! -L ${managementKeyFile}
        sed -n '1p' ${managementKeyFile}
        exit 0
      fi

      test -f ${managementKeyFile} && test ! -L ${managementKeyFile}
      install -d -m 0700 ${runtimeDirectory}
      header_file="$(mktemp ${runtimeDirectory}/.management-header.XXXXXX)"
      trap 'rm -f "$header_file"' EXIT
      printf 'X-Management-Key: %s\n' "$(tr -d '\r\n' < ${managementKeyFile})" > "$header_file"
      chmod 0600 "$header_file"
      endpoint=http://127.0.0.1:8317/v0/management/auth-files

      case "$action" in
        status)
          if [ "$#" -ne 1 ]; then exit 64; fi
          curl --fail --silent --show-error --header "@$header_file" "$endpoint" |
            jq '{observed_at, accounts: [.files[] | {
              name, provider, type, auth_index, label, note, email, account, account_type, status,
              disabled, unavailable, priority, quota, model_quotas, cooldowns,
              success, failed, last_refresh, next_retry_after, supports_quota
            }]}'
          ;;
        enable|disable)
          if [ "$#" -ne 2 ]; then exit 64; fi
          disabled=false
          if [ "$action" = disable ]; then disabled=true; fi
          jq -cn --arg name "$2" --argjson disabled "$disabled" '{name: $name, disabled: $disabled}' |
            curl --fail --silent --show-error --header "@$header_file" --header 'Content-Type: application/json' \
              --request PATCH --data-binary @- "$endpoint/status" | jq .
          ;;
        priority)
          if [ "$#" -ne 3 ] || ! printf '%s\n' "$3" | grep -Eq '^-?[0-9]+$'; then exit 64; fi
          jq -cn --arg name "$2" --argjson priority "$3" '{name: $name, priority: $priority}' |
            curl --fail --silent --show-error --header "@$header_file" --header 'Content-Type: application/json' \
              --request PATCH --data-binary @- "$endpoint/fields" | jq .
          ;;
        note)
          if [ "$#" -ne 3 ] || [ -z "$3" ]; then exit 64; fi
          jq -cn --arg name "$2" --arg note "$3" '{name: $name, note: $note}' |
            curl --fail --silent --show-error --header "@$header_file" --header 'Content-Type: application/json' \
              --request PATCH --data-binary @- "$endpoint/fields" | jq .
          ;;
        *) exit 64 ;;
      esac
    '';
  };
in
{
  options.dotfiles.cliproxyapi = {
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = package;
      description = "Pinned third-party CLIProxyAPI package";
    };
    release = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = release;
      description = "Pinned upstream CLIProxyAPI release";
    };
    artifactHash = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = artifact.hash;
      description = "Immutable hash of the selected upstream release artifact";
    };
    bind = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "127.0.0.1:8317";
      description = "Loopback-only CLIProxyAPI data-plane listener";
    };
    healthUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "http://127.0.0.1:8317/healthz";
      description = "Local CLIProxyAPI health endpoint";
    };
    canonicalBaseUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "https://cliproxyapi.lab.xavierchanth.xyz/v1";
      description = "Tailnet-only Responses-compatible gateway base URL";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = stateDirectory;
      description = "Service-owned persistent upstream authentication and proxy credential state";
    };
    authDirectory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = authDirectory;
      description = "Service-owned upstream authentication credential directory";
    };
    minimumUpstreamAccounts = lib.mkOption {
      type = lib.types.ints.positive;
      readOnly = true;
      default = 2;
      description = "Minimum distinct enabled upstream accounts required by the operating runbook";
    };
    managementKeyBytes = lib.mkOption {
      type = lib.types.ints.positive;
      readOnly = true;
      default = 24;
      description = "Random-byte count for the bcrypt-compatible loopback management key";
    };
    routingStrategy = lib.mkOption {
      type = lib.types.enum [ "round-robin" "fill-first" ];
      default = "round-robin";
      description = "Credential selection policy for eligible upstream accounts";
    };
    sessionAffinity = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Keep a client session on one eligible credential with automatic failover";
    };
    sessionAffinityTtl = lib.mkOption {
      type = lib.types.strMatching "^[1-9][0-9]*[smh]$";
      default = "1h";
      description = "Lifetime of upstream credential session bindings";
    };
    clients = lib.mkOption {
      type = lib.types.listOf (lib.types.enum [ "poseidon" "zeus" ]);
      readOnly = true;
      default = [ "poseidon" "zeus" ];
      description = "Independently revocable downstream client principals";
    };
    clientTemplate = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      default = clientTemplateText;
      description = "Secret-free optional Codex adapter template for the initial rollout";
    };
  };

  config = {
    users.groups.${serviceUser} = { };
    users.users.${serviceUser} = {
      isSystemUser = true;
      group = serviceUser;
      home = stateDirectory;
      description = "CLIProxyAPI service account";
    };
    environment.etc."cliproxyapi/codex-client.toml" = {
      mode = "0444";
      text = clientTemplateText;
    };
    environment.systemPackages = [ bootstrap clientToken accountControl ];
    dotfiles.labUpdate.requiredUnits = [ "cliproxyapi.service" ];

    systemd.services.cliproxyapi = {
      description = "Third-party provider-neutral subscription and API gateway";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig = {
        StartLimitIntervalSec = "5min";
        StartLimitBurst = 3;
      };
      serviceConfig = {
        Type = "simple";
        User = serviceUser;
        Group = serviceUser;
        StateDirectory = "cliproxyapi";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "cliproxyapi";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        WorkingDirectory = stateDirectory;
        ExecStartPre = "${prepare}/bin/cliproxyapi-prepare";
        ExecStart = "${package}/bin/cli-proxy-api -config ${runtimeConfig}";
        ExecStartPost = pkgs.writeShellScript "cliproxyapi-wait-healthy" ''
          set -eu
          for _attempt in $(${pkgs.coreutils}/bin/seq 1 30); do
            if ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 5 ${cfg.healthUrl} \
              | ${pkgs.jq}/bin/jq --exit-status '.status == "ok"' >/dev/null; then
              exit 0
            fi
            ${pkgs.coreutils}/bin/sleep 2
          done
          exit 1
        '';
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStartSec = "75s";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        ProcSubset = "pid";
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RemoveIPC = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
      };
    };
  };
}
