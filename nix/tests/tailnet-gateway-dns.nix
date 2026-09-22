{ lib, mkNixos, contextFor }:
let
  hades = (mkNixos "hades").config;
  dns = hades.dotfiles.tailnetGatewayDns;
  gateway = hades.dotfiles.serviceGateway;
  unit = hades.systemd.services.tailnet-gateway-dns;
in
assert builtins.elem "tailnet-gateway-dns" (contextFor "hades").groupNames;
assert dns.names == [ "xavierchanth.xyz" "lab.xavierchanth.xyz" "executor.lab.xavierchanth.xyz" "cliproxyapi.lab.xavierchanth.xyz" "cpamp.lab.xavierchanth.xyz" ];
assert dns.privateZone == "lab.xavierchanth.xyz";
assert lib.all (name: builtins.elem name dns.names) (builtins.attrNames gateway.routes);
assert lib.all (name: builtins.elem name dns.names) (builtins.attrNames gateway.redirects);
assert dns.ttl == 30;
assert dns.stateFile == "/var/lib/tailnet-gateway-dns/svc-lab-state.json";
assert builtins.elem "tailscaled.service" unit.after;
assert builtins.elem "svc-lab.service" unit.after;
assert builtins.elem "svc-lab.service" unit.requires;
assert lib.hasInfix "tailnet-gateway-dns-prepare" unit.serviceConfig.ExecStartPre;
assert lib.hasInfix "coredns" unit.serviceConfig.ExecStart;
assert hades.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [ 53 ];
assert hades.networking.firewall.interfaces.tailscale0.allowedUDPPorts == [ 53 ];
assert !(builtins.elem 53 hades.networking.firewall.allowedTCPPorts);
assert !(builtins.elem 53 hades.networking.firewall.allowedUDPPorts);
assert builtins.elem "tailnet-gateway-dns.service" hades.dotfiles.labUpdate.requiredUnits;
assert hades.systemd.timers.tailnet-gateway-dns-watchdog.wantedBy == [ "timers.target" ];
assert hades.systemd.timers.tailnet-gateway-dns-watchdog.timerConfig.OnUnitActiveSec == "30s";
assert lib.hasInfix "tailnet-gateway-dns-watchdog" hades.systemd.services.tailnet-gateway-dns-watchdog.serviceConfig.ExecStart;
true
