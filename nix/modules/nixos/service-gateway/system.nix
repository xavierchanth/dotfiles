{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.dotfiles.serviceGateway;
  routeNames = builtins.attrNames cfg.routes;
  upstreamUrl = route:
    let address = if route.upstream.address == "::1" then "[::1]" else route.upstream.address;
    in "http://${address}:${toString route.upstream.port}";
  upstreamUnits = lib.unique (lib.filter (unit: unit != null)
    (map (name: cfg.routes.${name}.upstreamUnit) routeNames));
  validHostname = hostname:
    builtins.match "^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$" hostname != null
    && builtins.match ".*\\.\\..*" hostname == null;
in
{
  options.dotfiles.serviceGateway.routes = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        upstream = mkOption {
          type = types.submodule {
            options = {
              address = mkOption {
                type = types.enum [ "127.0.0.1" "::1" ];
                description = "Loopback address of the upstream service.";
              };
              port = mkOption {
                type = types.port;
                description = "Loopback port of the upstream service.";
              };
            };
          };
          description = "HTTP loopback endpoint for this stable service origin.";
        };
        healthPath = mkOption {
          type = types.strMatching "^/[^[:space:]]*$";
          description = "Unauthenticated HTTP path used for active upstream health checks.";
        };
        upstreamUnit = mkOption {
          type = types.nullOr (types.strMatching "^[A-Za-z0-9@_.:-]+\\.service$");
          default = null;
          description = "Optional systemd service that Caddy should start after and weakly depend on.";
        };
      };
    });
    default = { };
    description = "Stable tailnet-only HTTPS origins, keyed by canonical hostname.";
  };

  config = {
    assertions = [
      {
        assertion = cfg.routes != { };
        message = "The service-gateway group requires at least one route";
      }
      {
        assertion = lib.all validHostname routeNames;
        message = "Service gateway route keys must be lowercase hostnames without empty labels";
      }
    ];

    services.caddy = {
      enable = true;
      openFirewall = false;
      virtualHosts = lib.mapAttrs (hostname: route: {
        hostName = hostname;
        extraConfig = ''
          tls internal
          reverse_proxy ${upstreamUrl route} {
            health_uri ${route.healthPath}
            health_interval 10s
            health_timeout 3s
            health_status 2xx
            flush_interval -1
          }
        '';
      }) cfg.routes;
    };

    # The interface-scoped firewall is the ingress boundary. Caddy deliberately
    # leaves the global firewall closed and also serves HTTP/3 on UDP 443.
    networking.firewall.interfaces.tailscale0 = {
      allowedTCPPorts = [ 80 443 ];
      allowedUDPPorts = [ 443 ];
    };

    systemd.services.caddy = {
      wants = upstreamUnits;
      after = [ "tailscaled.service" ] ++ upstreamUnits;
    };

    dotfiles.labUpdate.requiredUnits = [ "caddy.service" ];
  };
}
