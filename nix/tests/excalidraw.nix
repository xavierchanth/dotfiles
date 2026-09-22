{ lib, mkNixos, contextFor }:
let
  hades = (mkNixos "hades").config;
  poseidon = (mkNixos "poseidon").config;
  zeus = (mkNixos "zeus").config;
  cfg = hades.dotfiles.excalidraw;
  backend = hades.virtualisation.oci-containers.containers.excalidraw-backend;
  frontend = hades.virtualisation.oci-containers.containers.excalidraw;
  owners = lib.filter
    (name: builtins.elem "excalidraw" (contextFor name).groupNames)
    [ "hades" "poseidon" "zeus" ];
in
assert owners == [ "hades" ];
assert !(poseidon.virtualisation.oci-containers.containers ? excalidraw) && !(zeus.virtualisation.oci-containers.containers ? excalidraw);
assert cfg.backendImage == "docker.io/zimengxiong/excalidash-backend:0.6.0@sha256:cbdab75f31b21e342b464d6404a454791e5da7452e3614b137021a800fc4cac6";
assert cfg.frontendImage == "docker.io/zimengxiong/excalidash-frontend:0.6.0@sha256:4ec5b20c03034b96d37cfb87b5c39e9cc5958441a3abd8dcc413d11dfb11809c";
assert cfg.bind == "127.0.0.1:3100";
assert cfg.canonicalUrl == "https://excalidraw.lab.xavierchanth.xyz";
assert cfg.healthUrl == "http://127.0.0.1:3100/";
assert cfg.stateDirectory == "/var/lib/excalidraw";
assert cfg.databasePath == "/var/lib/excalidraw/excalidraw.db";
assert cfg.backupDirectory == "/var/backups/excalidraw";
assert cfg.persistence == "server-sqlite";
assert cfg.authMode == "local";
assert backend.serviceName == "excalidraw-backend";
assert backend.environment.DATABASE_URL == "file:/app/prisma/excalidraw.db";
assert backend.environment.BACKUP_DIR == "/app/backups";
assert backend.environment.BACKUP_RETENTION_DAYS == "14";
assert backend.volumes == [
  "/var/lib/excalidraw:/app/prisma"
  "/var/backups/excalidraw:/app/backups"
];
assert backend.podman.sdnotify == "healthy";
assert frontend.serviceName == "excalidraw";
assert frontend.dependsOn == [ "excalidraw-backend" ];
assert frontend.ports == [ "127.0.0.1:3100:80" ];
assert frontend.environment.BACKEND_URL == "excalidraw-backend:8000";
assert builtins.elem "excalidraw-backend.service" hades.dotfiles.labUpdate.requiredUnits;
assert builtins.elem "excalidraw.service" hades.dotfiles.labUpdate.requiredUnits;
assert !(builtins.elem 3100 hades.networking.firewall.allowedTCPPorts);
assert !(hades.systemd.services ? postgresql);
assert !(hades.systemd.services ? redis);
assert !(hades.systemd.services ? excalidraw-mcp);
true
