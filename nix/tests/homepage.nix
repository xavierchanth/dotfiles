{ mkNixos, contextFor, ... }:
let
  hades = (mkNixos "hades").config;
  homepage = hades.dotfiles.homepage;
  unit = hades.systemd.services.homepage;
in
assert builtins.elem "homepage" (contextFor "hades").groupNames;
assert homepage.image == "ghcr.io/gethomepage/homepage:v2.3.0@sha256:f820276654539cdc2cf0169f28188d135919a7984fad76d83d8d5ff1383f3705";
assert homepage.bind == "127.0.0.1:3000";
assert homepage.healthUrl == "http://127.0.0.1:3000/api/healthcheck";
assert homepage.restartPolicy == "unless-stopped";
assert homepage.allowedHosts == [ "lab.xavierchanth.xyz" ];
assert builtins.elem "homepage.service" hades.dotfiles.labUpdate.requiredUnits;
assert builtins.elem "docker.service" unit.requires;
assert builtins.elem "multi-user.target" unit.wantedBy;
assert unit.serviceConfig.Type == "oneshot" && unit.serviceConfig.RemainAfterExit;
assert !(builtins.elem 3000 hades.networking.firewall.allowedTCPPorts);
true
