{ config, lib, pkgs, ... }:
let
  release = "v1.12.14";
  version = lib.removePrefix "v" release;
  cfg = config.dotfiles.cpaManagerPlus;
  serviceUser = "cpa-manager-plus";
  stateDirectory = "/var/lib/cpa-manager-plus";
  databasePath = "${stateDirectory}/usage.sqlite";
  dataKeyPath = "${stateDirectory}/data.key";
  adminKeyFile = "${stateDirectory}/admin-key";
  artifacts = {
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-TDHPT8T/cgO7E3ZOfsWWUO6nm0K1y1e8T/wmfGKpTwM=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-F7aQ7CVSwl57kNHXCxFPbFvMjbBON8KorkjcLEqc6iY=";
    };
  };
  artifact = artifacts.${pkgs.stdenv.hostPlatform.system}
    or (throw "CPA Manager Plus does not provide a pinned artifact for ${pkgs.stdenv.hostPlatform.system}");
  source = pkgs.fetchurl {
    url = "https://github.com/seakee/CPA-Manager-Plus/releases/download/${release}/cpa-manager-plus_${release}_linux_${artifact.arch}.tar.gz";
    inherit (artifact) hash;
  };
  package = pkgs.stdenvNoCC.mkDerivation {
    pname = "cpa-manager-plus";
    inherit version;
    src = source;
    sourceRoot = "cpa-manager-plus_${release}_linux_${artifact.arch}";
    installPhase = ''
      runHook preInstall
      install -Dm0555 cpa-manager-plus "$out/bin/cpa-manager-plus"
      install -Dm0444 LICENSE "$out/share/licenses/cpa-manager-plus/LICENSE"
      runHook postInstall
    '';
  };
  prepare = pkgs.writeShellApplication {
    name = "cpa-manager-plus-prepare";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.openssl ];
    text = ''
      set -euo pipefail
      umask 077
      install -d -m 0700 ${stateDirectory}
      if [ ! -e ${adminKeyFile} ]; then
        temporary="$(mktemp ${stateDirectory}/.admin-key.XXXXXX)"
        trap 'rm -f "$temporary"' EXIT
        printf 'cpamp_%s\n' "$(openssl rand -hex 32)" > "$temporary"
        chmod 0600 "$temporary"
        mv "$temporary" ${adminKeyFile}
        trap - EXIT
      fi
      test -f ${adminKeyFile} && test ! -L ${adminKeyFile}
      chmod 0600 ${adminKeyFile}
      tr -d '\r\n' < ${adminKeyFile} | grep -Eq '^cpamp_[0-9a-f]{64}$'
    '';
  };
  adminKey = pkgs.writeShellApplication {
    name = "cpa-manager-plus-admin-key";
    runtimeInputs = [ pkgs.coreutils pkgs.openssl pkgs.systemd ];
    text = ''
      set -euo pipefail
      umask 077
      if [ "$(id -u)" -ne 0 ]; then
        echo 'cpa-manager-plus-admin-key must run as root' >&2
        exit 1
      fi
      if [ "$#" -ne 1 ]; then
        echo 'usage: cpa-manager-plus-admin-key show|rotate' >&2
        exit 64
      fi
      case "$1" in
        show)
          test -f ${adminKeyFile} && test ! -L ${adminKeyFile}
          sed -n '1p' ${adminKeyFile}
          ;;
        rotate)
          systemctl stop cpa-manager-plus.service
          temporary="$(mktemp ${stateDirectory}/.admin-key.XXXXXX)"
          trap 'rm -f "$temporary"; systemctl start cpa-manager-plus.service' EXIT
          printf 'cpamp_%s\n' "$(openssl rand -hex 32)" > "$temporary"
          chmod 0600 "$temporary"
          ${package}/bin/cpa-manager-plus reset-admin-key \
            --db-path ${databasePath} --admin-key-file "$temporary"
          install -m 0600 -o ${serviceUser} -g ${serviceUser} "$temporary" ${adminKeyFile}
          rm -f "$temporary"
          systemctl start cpa-manager-plus.service
          trap - EXIT
          printf 'rotated; retrieve the new key with the show action\n'
          ;;
        *) exit 64 ;;
      esac
    '';
  };
in
{
  options.dotfiles.cpaManagerPlus = {
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = package;
      description = "Pinned third-party CPA Manager Plus package";
    };
    release = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = release;
      description = "Pinned upstream CPA Manager Plus release";
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
      default = "127.0.0.1:18317";
      description = "Loopback-only Manager Server listener";
    };
    healthUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "http://127.0.0.1:18317/health";
      description = "Local Manager Server health endpoint";
    };
    canonicalUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "https://cpamp.lab.xavierchanth.xyz";
      description = "Tailnet-only administrative origin";
    };
    cpaUpstreamUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "http://127.0.0.1:8317";
      description = "Loopback CLIProxyAPI management upstream entered during first setup";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = stateDirectory;
      description = "Persistent SQLite, encryption-key, and admin-key state";
    };
  };

  config = {
    users.groups.${serviceUser} = { };
    users.users.${serviceUser} = {
      isSystemUser = true;
      group = serviceUser;
      home = stateDirectory;
      description = "CPA Manager Plus service account";
    };
    environment.systemPackages = [ adminKey ];
    dotfiles.labUpdate.requiredUnits = [ "cpa-manager-plus.service" ];

    systemd.services.cpa-manager-plus = {
      description = "Third-party CLIProxyAPI operations dashboard";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "cliproxyapi.service" ];
      wants = [ "network-online.target" "cliproxyapi.service" ];
      environment = {
        HTTP_ADDR = cfg.bind;
        USAGE_DB_PATH = databasePath;
        CPA_MANAGER_DATA_KEY_PATH = dataKeyPath;
        CPA_MANAGER_ADMIN_KEY_FILE = adminKeyFile;
        USAGE_CORS_ORIGINS = cfg.canonicalUrl;
        CPAMP_UPDATE_CHECK_ENABLED = "false";
      };
      serviceConfig = {
        Type = "simple";
        User = serviceUser;
        Group = serviceUser;
        StateDirectory = "cpa-manager-plus";
        StateDirectoryMode = "0700";
        UMask = "0077";
        WorkingDirectory = stateDirectory;
        ExecStartPre = "${prepare}/bin/cpa-manager-plus-prepare";
        ExecStart = "${package}/bin/cpa-manager-plus";
        ExecStartPost = pkgs.writeShellScript "cpa-manager-plus-wait-healthy" ''
          set -eu
          for _attempt in $(${pkgs.coreutils}/bin/seq 1 60); do
            if ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 5 ${cfg.healthUrl} \
              | ${pkgs.jq}/bin/jq --exit-status '.ok == true and .service == "cpa-manager-plus"' >/dev/null; then
              exit 0
            fi
            ${pkgs.coreutils}/bin/sleep 2
          done
          exit 1
        '';
        Restart = "on-failure";
        RestartSec = "5s";
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
