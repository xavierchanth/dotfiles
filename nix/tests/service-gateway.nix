{ lib, mkNixos, contextFor }:
let
  hostname = "executor.lab.xavierchanth.xyz";
  hades = (mkNixos "hades").config;
  poseidon = (mkNixos "poseidon").config;
  zeus = (mkNixos "zeus").config;
  route = hades.dotfiles.serviceGateway.routes.${hostname};
  vhost = hades.services.caddy.virtualHosts.${hostname};
  caddy = hades.systemd.services.caddy;
  gatewayHosts = lib.filter
    (name: builtins.elem "service-gateway" (contextFor name).groupNames)
    [ "hades" "poseidon" "zeus" ];
in
assert gatewayHosts == [ "hades" ];
assert hades.services.caddy.enable;
assert !poseidon.services.caddy.enable && !zeus.services.caddy.enable;
assert builtins.attrNames hades.dotfiles.serviceGateway.routes == [ hostname ];
assert route.upstream.address == "127.0.0.1" && route.upstream.port == 4788;
assert route.healthPath == "/api/health" && route.upstreamUnit == "executor.service";
assert vhost.hostName == hostname;
assert lib.hasInfix "tls internal" vhost.extraConfig;
assert lib.hasInfix "reverse_proxy http://127.0.0.1:4788" vhost.extraConfig;
assert lib.hasInfix "health_uri /api/health" vhost.extraConfig;
assert lib.hasInfix "health_status 2xx" vhost.extraConfig;
assert lib.hasInfix "flush_interval -1" vhost.extraConfig;
assert !lib.hasInfix "request_body" vhost.extraConfig;
assert !lib.hasInfix "basic_auth" vhost.extraConfig;
assert !lib.hasInfix "header_up" vhost.extraConfig;
assert !lib.hasInfix "stream_timeout" vhost.extraConfig;
assert !hades.services.caddy.openFirewall;
assert lib.all (port: builtins.elem port hades.networking.firewall.interfaces.tailscale0.allowedTCPPorts) [ 80 443 ];
assert builtins.elem 443 hades.networking.firewall.interfaces.tailscale0.allowedUDPPorts;
assert lib.all (port: !(builtins.elem port hades.networking.firewall.allowedTCPPorts)) [ 80 443 ];
assert !(builtins.elem 443 hades.networking.firewall.allowedUDPPorts);
assert builtins.elem "executor.service" caddy.wants;
assert builtins.elem "executor.service" caddy.after;
assert builtins.elem "tailscaled.service" caddy.after;
assert builtins.elem "caddy.service" hades.dotfiles.labUpdate.requiredUnits;
true
