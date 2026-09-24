{ config, lib, pkgs, ... }:
let
  release = "v2.3.0";
  imageDigest = "sha256:f820276654539cdc2cf0169f28188d135919a7984fad76d83d8d5ff1383f3705";
  homepage = config.dotfiles.homepage;
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
      columns = 1;
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
          Excalidraw = {
            description = "Persistent private diagram workspace";
            href = "https://excalidraw.lab.xavierchanth.xyz";
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
    allowedHosts = lib.mkOption {
      type = lib.types.nonEmptyListOf (lib.types.strMatching "^[A-Za-z0-9.-]+(:[0-9]+)?$");
      default = [ "lab.xavierchanth.xyz" "lab.xavierchanth.xyz:${toString config.dotfiles.serviceGateway.httpsPort}" ];
      description = "Canonical ingress hosts accepted by Homepage";
    };
    serviceNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = [ "Executor" "Excalidraw" ];
      description = "Names in the generated Homepage service catalog.";
    };
  };

  config = {
    assertions = [{
      assertion = config.virtualisation.oci-containers.backend == "podman";
      message = "Homepage requires the Podman host group";
    }];

    dotfiles.labUpdate.requiredUnits = [ "homepage.service" ];

    virtualisation.oci-containers.containers.homepage = {
      serviceName = "homepage";
      image = homepage.image;
      pull = "missing";
      ports = [ "${homepage.bind}:3000" ];
      environment = {
        HOMEPAGE_ALLOWED_HOSTS = lib.concatStringsSep "," homepage.allowedHosts;
        LOG_TARGETS = "stdout";
      };
      volumes = [ "${configDirectory}:/app/config:ro" ];
      podman.sdnotify = "healthy";
      extraOptions = [
        "--health-cmd=wget --quiet --tries=1 --spider http://127.0.0.1:3000/api/healthcheck"
        "--health-interval=30s"
        "--health-timeout=5s"
        "--health-retries=5"
        "--health-start-period=20s"
      ];
    };

    systemd.services.homepage.serviceConfig.TimeoutStartSec = lib.mkForce "10min";
  };
}
