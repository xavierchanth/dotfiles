{ mkNixos, contextFor, ... }:
let
  hades = (mkNixos "hades").config;
  homepage = hades.dotfiles.homepage;
  container = hades.virtualisation.oci-containers.containers.homepage;
  unit = hades.systemd.services.homepage;
in
assert builtins.elem "homepage" (contextFor "hades").groupNames;
assert homepage.image == "ghcr.io/gethomepage/homepage:v2.3.0@sha256:f820276654539cdc2cf0169f28188d135919a7984fad76d83d8d5ff1383f3705";
assert homepage.bind == "127.0.0.1:3000";
assert homepage.healthUrl == "http://127.0.0.1:3000/api/healthcheck";
assert homepage.allowedHosts == [ "lab.xavierchanth.xyz" ];
assert homepage.serviceNames == [ "Executor" ];
assert container.serviceName == "homepage";
assert container.image == homepage.image;
assert container.ports == [ "127.0.0.1:3000:3000" ];
assert container.podman.sdnotify == "healthy";
assert builtins.elem "homepage.service" hades.dotfiles.labUpdate.requiredUnits;
assert unit.serviceConfig.Type == "notify";
assert !(builtins.elem 3000 hades.networking.firewall.allowedTCPPorts);
true
