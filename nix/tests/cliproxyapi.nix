{ lib, mkNixos, contextFor, ... }:
let
  hades = (mkNixos "hades").config;
  proxy = hades.dotfiles.cliproxyapi;
  unit = hades.systemd.services.cliproxyapi;
in
assert builtins.elem "cliproxyapi" (contextFor "hades").groupNames;
assert proxy.release == "v7.3.5";
assert proxy.artifactHash == "sha256-BBUFGj7Y5cZZ7acBfvRddLV0sfR07ogMsrktpEu2H7M=";
assert proxy.bind == "127.0.0.1:8317";
assert proxy.healthUrl == "http://127.0.0.1:8317/healthz";
assert proxy.canonicalBaseUrl == "https://cliproxyapi.lab.xavierchanth.xyz/v1";
assert proxy.stateDirectory == "/var/lib/cliproxyapi";
assert proxy.authDirectory == "/var/lib/cliproxyapi/auth";
assert proxy.minimumUpstreamAccounts == 2;
assert proxy.managementKeyBytes == 24;
assert 15 + (proxy.managementKeyBytes * 2) <= 72;
assert proxy.routingStrategy == "round-robin";
assert proxy.sessionAffinity && proxy.sessionAffinityTtl == "1h";
assert proxy.clients == [ "poseidon" "zeus" ];
assert lib.hasInfix "env_key = \"CLIPROXYAPI_TOKEN\"" proxy.clientTemplate;
assert lib.hasInfix "wire_api = \"responses\"" proxy.clientTemplate;
assert lib.hasInfix "supports_websockets = true" proxy.clientTemplate;
assert !(lib.hasInfix "cpa_poseidon_" proxy.clientTemplate) && !(lib.hasInfix "cpa_zeus_" proxy.clientTemplate);
assert unit.serviceConfig.User == "cliproxyapi" && unit.serviceConfig.Group == "cliproxyapi";
assert unit.serviceConfig.StateDirectoryMode == "0700" && unit.serviceConfig.RuntimeDirectoryMode == "0700";
assert unit.serviceConfig.Restart == "on-failure";
assert unit.serviceConfig.TimeoutStartSec == "75s";
assert unit.unitConfig.StartLimitBurst == 3 && unit.unitConfig.StartLimitIntervalSec == "5min";
assert unit.serviceConfig.NoNewPrivileges && unit.serviceConfig.ProtectSystem == "strict";
assert !(lib.hasInfix "cpa_" unit.serviceConfig.ExecStart);
assert !(lib.hasInfix "management-key" unit.serviceConfig.ExecStart);
assert builtins.elem "cliproxyapi.service" hades.dotfiles.labUpdate.requiredUnits;
assert lib.any (package: lib.getName package == "cliproxyapi-account") hades.environment.systemPackages;
assert !(builtins.elem 8317 hades.networking.firewall.allowedTCPPorts);
true
