{ config, lib, pkgs, ... }:
let
  release = "v1.6.8";
  imageDigest = "sha256:527e014ce0641e9d569314561fba2a37b872ffd5074471b9bc48b66611ecb090";
  executor = config.dotfiles.executor;
  image = executor.image;
  stateDirectory = executor.stateDirectory;
  dataDirectory = executor.dataDirectory;
  backupDirectory = "/var/backups/executor";
  composePath = "${stateDirectory}/docker-compose.yml";
  composeFile = pkgs.writeText "executor-${release}-docker-compose.yml" ''
    services:
      executor:
        image: ${image}
        restart: unless-stopped
        ports:
          - "${executor.bind}:4788"
        environment:
          EXECUTOR_WEB_BASE_URL: "${executor.webBaseUrl}"
          EXECUTOR_ALLOW_LOCAL_NETWORK: "${lib.boolToString executor.allowLocalNetwork}"
          EXECUTOR_ALLOW_STDIO_MCP: "${lib.boolToString executor.allowStdioMcp}"
        volumes:
          - "${dataDirectory}:/data"
        healthcheck:
          test:
            - CMD
            - bun
            - -e
            - "fetch('http://127.0.0.1:4788/api/health').then(async r=>process.exit(r.ok&&(await r.json()).status==='ok'?0:1),()=>process.exit(1))"
          interval: 30s
          timeout: 5s
          retries: 5
          start_period: 20s
  '';
  compose = "${pkgs.docker-compose}/bin/docker-compose --project-name executor --file ${composePath}";
  offsite = config.dotfiles.executor.offsiteBackup;
  prepare = pkgs.writeShellApplication {
    name = "executor-prepare";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu
      install -d -m 0750 -o root -g root ${stateDirectory}
      install -d -m 0700 -o root -g root ${backupDirectory}
      install -d -m 0750 -o 65532 -g 65532 ${dataDirectory}
      chown 65532:65532 ${dataDirectory}
      chmod 0750 ${dataDirectory}
      install -m 0444 -o root -g root ${composeFile} ${composePath}
    '';
  };
  backup = pkgs.writeShellApplication {
    name = "executor-backup";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.findutils pkgs.gnutar pkgs.gzip pkgs.docker pkgs.docker-compose pkgs.jq pkgs.systemd ];
    text = ''
      set -euo pipefail
      umask 077
      stamp="$(date -u +%Y%m%dT%H%M%SZ)"
      temporary="${backupDirectory}/.$stamp.tmp"
      destination="${backupDirectory}/$stamp"
      running=0

      wait_healthy() {
        for _attempt in $(seq 1 60); do
          if curl --fail --silent --show-error --max-time 5 ${executor.healthUrl} \
            | jq --exit-status '.status == "ok"' >/dev/null; then
            return 0
          fi
          sleep 5
        done
        return 1
      }

      recover() {
        ${compose} start >/dev/null && wait_healthy
      }

      mark_unhealthy() {
        ${compose} down >/dev/null 2>&1 || true
        systemctl --no-block stop executor.service || true
      }

      cleanup() {
        status=$?
        if [ "$running" -eq 1 ]; then
          if ! recover; then
            mark_unhealthy
            status=1
          fi
        fi
        rm -rf -- "$temporary"
        exit "$status"
      }
      trap cleanup EXIT INT TERM
      install -d -m 0700 "$temporary"

      running=1
      ${compose} stop --timeout 60
      tar --numeric-owner -C /var/lib -czf "$temporary/executor-state.tar.gz" executor
      {
        printf 'release=%s\n' '${release}'
        printf 'image=%s\n' '${image}'
        printf 'created_at=%s\n' "$stamp"
        printf '\ncompose_config:\n'
        ${compose} config
        printf '\ncontainer_images:\n'
        ${compose} images
      } > "$temporary/manifest.txt"
      (cd "$temporary" && sha256sum executor-state.tar.gz manifest.txt > SHA256SUMS)
      if ! recover; then
        running=0
        mark_unhealthy
        exit 1
      fi
      running=0

      mv "$temporary" "$destination"
      trap - EXIT INT TERM
      find ${backupDirectory} -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +14 -exec rm -rf -- {} +
    '';
  };
  repositoryArgs = ''--repository-file "$CREDENTIALS_DIRECTORY/repository" --password-file "$CREDENTIALS_DIRECTORY/password"'';
  restoreCheck = pkgs.writeShellApplication {
    name = "executor-restore-check";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.gnutar pkgs.restic ];
    text = ''
      set -euo pipefail
      umask 077
      snapshot_id="''${1:-}"
      temporary="$(mktemp -d /tmp/executor-restore-check.XXXXXX)"
      trap 'rm -rf -- "$temporary"' EXIT

      if [ -z "$snapshot_id" ]; then
        snapshot_id="$(restic ${repositoryArgs} snapshots --json --tag executor --tag hades --path ${backupDirectory} \
          | jq -r 'sort_by(.time) | last | .id // empty')"
      fi
      test -n "$snapshot_id"
      restic ${repositoryArgs} restore "$snapshot_id" --target "$temporary" \
        --include '${backupDirectory}' --include '${backupDirectory}/**'
      restored="$(find "$temporary/var/backups/executor" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort | tail -n 1)"
      test -n "$restored"
      (cd "$restored" && sha256sum --check SHA256SUMS)
      tar -tzf "$restored/executor-state.tar.gz" > "$temporary/archive.list"
      grep -q '^executor/data/' "$temporary/archive.list"
      grep -q '^image=${image}$' "$restored/manifest.txt"
    '';
  };
  offsiteBackup = pkgs.writeShellApplication {
    name = "executor-offsite-backup";
    runtimeInputs = [ pkgs.jq pkgs.restic ];
    text = ''
      set -euo pipefail
      snapshot_id="$(restic ${repositoryArgs} backup ${backupDirectory} --tag executor --tag hades --json \
        | jq -r 'select(.message_type == "summary") | .snapshot_id // empty')"
      test -n "$snapshot_id"
      ${restoreCheck}/bin/executor-restore-check "$snapshot_id"
    '';
  };
  repositoryPreflight = pkgs.writeShellApplication {
    name = "executor-backup-preflight";
    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.restic ];
    text = ''
      set -euo pipefail
      repository="$(tr -d '\r\n' < "$CREDENTIALS_DIRECTORY/repository")"
      case "$repository" in
        sftp:*|rest:https://*|s3:*|b2:*|azure:*|gs:*|rclone:*) ;;
        *) echo "Executor backup repository must use an off-host transport" >&2; exit 1 ;;
      esac
      case "$repository" in
        *localhost*|*127.0.0.1*|*'[::1]'*) echo "Executor backup repository must not resolve to loopback" >&2; exit 1 ;;
      esac

      expected="$(tr -d '\r\n' < "$CREDENTIALS_DIRECTORY/expected-repository-id")"
      test -n "$expected"
      actual="$(restic ${repositoryArgs} cat config | jq -r '.id // empty')"
      test -n "$actual"
      if [ "$actual" != "$expected" ]; then
        echo "Executor backup repository identity mismatch" >&2
        exit 1
      fi
    '';
  };
in
{
  options.dotfiles.executor = {
    image = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "ghcr.io/usefulsoftwareco/executor-selfhost:${release}@${imageDigest}";
      description = "Immutable Executor container image reference";
    };
    bind = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "127.0.0.1:4788";
      description = "Loopback-only published address for Executor";
    };
    webBaseUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "https://executor.lab.xavierchanth.xyz";
      description = "Canonical browser and OAuth base URL";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/var/lib/executor";
      description = "Executor persistent state root";
    };
    dataDirectory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/var/lib/executor/data";
      description = "Executor container data bind mount source";
    };
    healthUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "http://127.0.0.1:4788/api/health";
      description = "Local Executor readiness endpoint";
    };
    allowLocalNetwork = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = false;
      description = "Whether sandboxed tools may access private networks";
    };
    allowStdioMcp = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      default = false;
      description = "Whether integrations may launch local stdio MCP processes";
    };
    offsiteBackup = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Upload and verify Executor backups in an off-host restic repository";
    };
    repositoryCredentialPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/keys/executor-restic-repository";
      description = "Runtime-only file containing the restic repository URI";
    };
    passwordCredentialPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/keys/executor-restic-password";
      description = "Runtime-only file containing the restic repository password";
    };
    expectedRepositoryIdCredentialPath = lib.mkOption {
      type = lib.types.str;
      default = "/run/keys/executor-restic-expected-repository-id";
      description = "Runtime-only file pinning the expected restic repository ID";
    };
    };
  };

  config = {
  assertions = [{
    assertion = config.virtualisation.docker.enable;
    message = "Executor requires the Docker host group";
  }];

  dotfiles.labUpdate.requiredUnits = [ "executor.service" ];

  systemd.services.executor = {
    description = "Executor MCP gateway and capability manager";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "network-online.target" ]
      ++ lib.optionals offsite.enable [ "executor-backup-preflight.service" ];
    requires = [ "docker.service" ]
      ++ lib.optionals offsite.enable [ "executor-backup-preflight.service" ];
    wants = [ "network-online.target" ];
    environment.COMPOSE_PROJECT_NAME = "executor";
    path = [ pkgs.curl pkgs.docker pkgs.docker-compose pkgs.jq ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      Group = "root";
      UMask = "0027";
      TimeoutStartSec = "10min";
      TimeoutStopSec = "2min";
      ExecStartPre = "${prepare}/bin/executor-prepare";
      ExecStart = "${compose} up --detach --remove-orphans";
      ExecStartPost = pkgs.writeShellScript "executor-wait-healthy" ''
        set -eu
        for attempt in $(${pkgs.coreutils}/bin/seq 1 60); do
          if ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 5 ${executor.healthUrl} \
            | ${pkgs.jq}/bin/jq --exit-status '.status == "ok"' >/dev/null; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 5
        done
        ${compose} ps >&2
        ${compose} logs --tail 100 >&2
        exit 1
      '';
      ExecStop = "${compose} down";
    };
  };

  systemd.services.executor-backup-preflight = lib.mkIf offsite.enable {
    description = "Verify Executor off-host backup destination and credentials";
    before = [ "executor.service" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      Group = "root";
      UMask = "0077";
      LoadCredential = [
        "repository:${offsite.repositoryCredentialPath}"
        "password:${offsite.passwordCredentialPath}"
        "expected-repository-id:${offsite.expectedRepositoryIdCredentialPath}"
      ];
      ExecStart = "${repositoryPreflight}/bin/executor-backup-preflight";
    };
  };

  systemd.services.executor-backup = {
    description = "Back up complete Executor state and release manifest";
    after = [ "executor.service" ];
    requires = [ "executor.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      UMask = "0077";
      ExecStart = "${backup}/bin/executor-backup";
    };
  };

  systemd.services.executor-restore-check = lib.mkIf offsite.enable {
    description = "Verify an Executor backup by restoring it from off-host storage";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      UMask = "0077";
      LoadCredential = [
        "repository:${offsite.repositoryCredentialPath}"
        "password:${offsite.passwordCredentialPath}"
        "expected-repository-id:${offsite.expectedRepositoryIdCredentialPath}"
      ];
      ExecStartPre = "${repositoryPreflight}/bin/executor-backup-preflight";
      ExecStart = "${restoreCheck}/bin/executor-restore-check";
    };
  };

  systemd.services.executor-offsite-backup = lib.mkIf offsite.enable {
    description = "Upload and verify the Executor backup off host";
    requires = [ "executor-backup.service" ];
    after = [ "executor-backup.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      UMask = "0077";
      LoadCredential = [
        "repository:${offsite.repositoryCredentialPath}"
        "password:${offsite.passwordCredentialPath}"
        "expected-repository-id:${offsite.expectedRepositoryIdCredentialPath}"
      ];
      ExecStartPre = "${repositoryPreflight}/bin/executor-backup-preflight";
      ExecStart = "${offsiteBackup}/bin/executor-offsite-backup";
    };
  };

  systemd.timers.executor-backup = {
    description = "Daily Executor backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:40:00";
      Persistent = true;
      RandomizedDelaySec = "20min";
      Unit = if offsite.enable then "executor-offsite-backup.service" else "executor-backup.service";
    };
  };
  };
}
