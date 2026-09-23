{ config, lib, pkgs, ... }:
let
  release = "0.6.0";
  backendDigest = "sha256:cbdab75f31b21e342b464d6404a454791e5da7452e3614b137021a800fc4cac6";
  frontendDigest = "sha256:4ec5b20c03034b96d37cfb87b5c39e9cc5958441a3abd8dcc413d11dfb11809c";
  cfg = config.dotfiles.excalidraw;
  prepare = pkgs.writeShellApplication {
    name = "excalidraw-prepare";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu
      install -d -m 0750 -o 1001 -g 1001 ${cfg.stateDirectory}
      install -d -m 0700 -o 1001 -g 1001 ${cfg.backupDirectory}
      chown 1001:1001 ${cfg.stateDirectory} ${cfg.backupDirectory}
      chmod 0750 ${cfg.stateDirectory}
      chmod 0700 ${cfg.backupDirectory}
    '';
  };
in
{
  options.dotfiles.excalidraw = {
    backendImage = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "docker.io/zimengxiong/excalidash-backend:${release}@${backendDigest}";
      description = "Immutable ExcaliDash backend image reference.";
    };
    frontendImage = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "docker.io/zimengxiong/excalidash-frontend:${release}@${frontendDigest}";
      description = "Immutable ExcaliDash frontend image reference.";
    };
    bind = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "127.0.0.1:3100";
      description = "Loopback-only published address for ExcaliDash.";
    };
    canonicalUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "https://excalidraw.lab.xavierchanth.xyz";
      description = "Tailnet-only canonical ExcaliDash origin.";
    };
    healthUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "http://127.0.0.1:3100/";
      description = "Local ExcaliDash frontend readiness endpoint.";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/var/lib/excalidraw";
      description = "Persistent ExcaliDash database and generated-secret directory.";
    };
    databasePath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/var/lib/excalidraw/excalidraw.db";
      description = "Host path of the ExcaliDash SQLite database.";
    };
    backupDirectory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "/var/backups/excalidraw";
      description = "Persistent destination for scheduled ExcaliDash SQLite backups.";
    };
    persistence = lib.mkOption {
      type = lib.types.enum [ "server-sqlite" ];
      readOnly = true;
      default = "server-sqlite";
      description = "Authoritative diagram persistence model.";
    };
    authMode = lib.mkOption {
      type = lib.types.enum [ "local" ];
      readOnly = true;
      default = "local";
      description = "ExcaliDash authentication mode.";
    };
  };

  config = {
    assertions = [{
      assertion = config.virtualisation.oci-containers.backend == "podman";
      message = "ExcaliDash requires the Podman host group";
    }];

    dotfiles.labUpdate.requiredUnits = [
      "excalidraw-backend.service"
      "excalidraw.service"
    ];

    virtualisation.oci-containers.containers = {
      excalidraw-backend = {
        serviceName = "excalidraw-backend";
        image = cfg.backendImage;
        pull = "missing";
        environment = {
          DATABASE_PROVIDER = "sqlite";
          DATABASE_URL = "file:/app/prisma/excalidraw.db";
          PORT = "8000";
          NODE_ENV = "production";
          AUTH_MODE = cfg.authMode;
          FRONTEND_URL = cfg.canonicalUrl;
          TRUST_PROXY = "1";
          ENFORCE_HTTPS_REDIRECT = "false";
          UPDATE_CHECK_OUTBOUND = "false";
          BACKUP_SCHEDULE = "0 0 4 * * *";
          BACKUP_DIR = "/app/backups";
          BACKUP_RETENTION_DAYS = "14";
        };
        volumes = [
          "${cfg.stateDirectory}:/app/prisma"
          "${cfg.backupDirectory}:/app/backups"
        ];
        podman.sdnotify = "healthy";
        extraOptions = [
          "--health-cmd=node -e require('http').get('http://127.0.0.1:8000/health',(r)=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"
          "--health-interval=30s"
          "--health-timeout=10s"
          "--health-retries=3"
          "--health-start-period=30s"
        ];
      };

      excalidraw = {
        serviceName = "excalidraw";
        image = cfg.frontendImage;
        pull = "missing";
        dependsOn = [ "excalidraw-backend" ];
        ports = [ "${cfg.bind}:80" ];
        environment.BACKEND_URL = "excalidraw-backend:8000";
        podman.sdnotify = "healthy";
        extraOptions = [
          "--health-cmd=wget --quiet --tries=1 --spider http://127.0.0.1:80"
          "--health-interval=30s"
          "--health-timeout=10s"
          "--health-retries=3"
          "--health-start-period=20s"
        ];
      };
    };

    systemd.services.excalidraw-backend = {
      description = "ExcaliDash persistent diagram backend (Podman)";
      serviceConfig.ExecStartPre = lib.mkBefore [ "${prepare}/bin/excalidraw-prepare" ];
    };
    systemd.services.excalidraw.description = "ExcaliDash frontend (Podman)";
  };
}
