{ config, lib, pkgs, ... }:
let
  release = "v2.3.0";
  imageDigest = "sha256:f820276654539cdc2cf0169f28188d135919a7984fad76d83d8d5ff1383f3705";
  homepage = config.dotfiles.homepage;
  stateDirectory = "/var/lib/homepage";
  composePath = "${stateDirectory}/docker-compose.yml";
  yaml = pkgs.formats.yaml { };

  settings = yaml.generate "settings.yaml" {
    title = "Xavier's Lab";
    description = "Personal lab services";
    theme = "dark";
    color = "slate";
    headerStyle = "clean";
    statusStyle = "dot";
    target = "_self";
    hideVersion = true;
    disableUpdateCheck = true;
    layout.Lab = {
      style = "row";
      columns = 2;
    };
  };
  services = yaml.generate "services.yaml" [
    {
      Lab = [
        {
          Executor = {
            description = "MCP gateway and capability manager";
            href = "https://executor.lab.xavierchanth.xyz";
          };
        }
        {
          Plane = {
            description = "Human-visible work ledger";
            href = "https://plane.lab.xavierchanth.xyz";
          };
        }
      ];
    }
  ];
  emptyList = yaml.generate "empty.yaml" [ ];
  emptyAttrs = yaml.generate "empty-attrs.yaml" { };
  configDirectory = pkgs.runCommand "homepage-${release}-config" { } ''
    mkdir -p "$out"
    cp ${settings} "$out/settings.yaml"
    cp ${services} "$out/services.yaml"
    cp ${emptyList} "$out/bookmarks.yaml"
    cp ${emptyList} "$out/widgets.yaml"
    cp ${emptyAttrs} "$out/docker.yaml"
    cp ${emptyAttrs} "$out/kubernetes.yaml"
    touch "$out/custom.css" "$out/custom.js"
  '';
  composeFile = pkgs.writeText "homepage-${release}-docker-compose.yml" ''
    services:
      homepage:
        image: ${homepage.image}
        restart: ${homepage.restartPolicy}
        ports:
          - "${homepage.bind}:3000"
        environment:
          HOMEPAGE_ALLOWED_HOSTS: "${lib.concatStringsSep "," homepage.allowedHosts}"
          LOG_TARGETS: stdout
        volumes:
          - "${configDirectory}:/app/config:ro"
  '';
  compose = "${pkgs.docker-compose}/bin/docker-compose --project-name homepage --file ${composePath}";
  prepare = pkgs.writeShellApplication {
    name = "homepage-prepare";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu
      install -d -m 0750 -o root -g root ${stateDirectory}
      install -m 0444 -o root -g root ${composeFile} ${composePath}
    '';
  };
in
{
  options.dotfiles.homepage = {
    image = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "ghcr.io/gethomepage/homepage:${release}@${imageDigest}";
      description = "Immutable Homepage container image reference";
    };
    bind = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "127.0.0.1:3000";
      description = "Loopback-only published address for Homepage";
    };
    healthUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "http://127.0.0.1:3000/api/healthcheck";
      description = "Local Homepage readiness endpoint";
    };
    restartPolicy = lib.mkOption {
      type = lib.types.enum [ "unless-stopped" ];
      readOnly = true;
      default = "unless-stopped";
      description = "Container restart policy used beneath the systemd lifecycle";
    };
    allowedHosts = lib.mkOption {
      type = lib.types.nonEmptyListOf (lib.types.strMatching "^[A-Za-z0-9.-]+(:[0-9]+)?$");
      default = [ "lab.xavierchanth.xyz" ];
      description = "Canonical ingress hosts accepted by Homepage";
    };
  };

  config = {
    assertions = [{
      assertion = config.virtualisation.docker.enable;
      message = "Homepage requires the Docker host group";
    }];

    dotfiles.labUpdate.requiredUnits = [ "homepage.service" ];

    systemd.services.homepage = {
      description = "Homepage personal lab dashboard";
      wantedBy = [ "multi-user.target" ];
      after = [ "docker.service" "network-online.target" ];
      requires = [ "docker.service" ];
      wants = [ "network-online.target" ];
      environment.COMPOSE_PROJECT_NAME = "homepage";
      path = [ pkgs.curl pkgs.docker pkgs.docker-compose ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
        Group = "root";
        UMask = "0027";
        TimeoutStartSec = "5min";
        TimeoutStopSec = "2min";
        ExecStartPre = "${prepare}/bin/homepage-prepare";
        ExecStart = "${compose} up --detach --remove-orphans";
        ExecStartPost = pkgs.writeShellScript "homepage-wait-healthy" ''
          set -eu
          for attempt in $(${pkgs.coreutils}/bin/seq 1 60); do
            if ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 5 ${homepage.healthUrl} >/dev/null; then
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
  };
}
