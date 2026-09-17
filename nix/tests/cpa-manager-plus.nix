{ lib, mkNixos, contextFor, ... }:
let
  hades = (mkNixos "hades").config;
  manager = hades.dotfiles.cpaManagerPlus;
  unit = hades.systemd.services.cpa-manager-plus;
in
assert builtins.elem "cpa-manager-plus" (contextFor "hades").groupNames;
assert manager.release == "v1.12.14";
assert manager.artifactHash == "sha256-TDHPT8T/cgO7E3ZOfsWWUO6nm0K1y1e8T/wmfGKpTwM=";
assert manager.bind == "127.0.0.1:18317";
assert manager.healthUrl == "http://127.0.0.1:18317/health";
assert manager.canonicalUrl == "https://cpamp.lab.xavierchanth.xyz";
assert manager.cpaUpstreamUrl == "http://127.0.0.1:8317";
assert manager.stateDirectory == "/var/lib/cpa-manager-plus";
assert unit.environment.HTTP_ADDR == manager.bind;
assert unit.environment.USAGE_DB_PATH == "/var/lib/cpa-manager-plus/usage.sqlite";
assert unit.environment.CPA_MANAGER_DATA_KEY_PATH == "/var/lib/cpa-manager-plus/data.key";
assert unit.environment.CPA_MANAGER_ADMIN_KEY_FILE == "/var/lib/cpa-manager-plus/admin-key";
assert unit.environment.USAGE_CORS_ORIGINS == manager.canonicalUrl;
assert unit.environment.CPAMP_UPDATE_CHECK_ENABLED == "false";
assert unit.serviceConfig.User == "cpa-manager-plus" && unit.serviceConfig.Group == "cpa-manager-plus";
assert unit.serviceConfig.StateDirectoryMode == "0700" && unit.serviceConfig.UMask == "0077";
assert unit.serviceConfig.Restart == "on-failure";
assert unit.serviceConfig.NoNewPrivileges && unit.serviceConfig.ProtectSystem == "strict";
assert builtins.elem "cliproxyapi.service" unit.after && builtins.elem "cliproxyapi.service" unit.wants;
assert !(lib.hasInfix "CPA_MANAGEMENT_KEY" (builtins.toJSON unit.environment));
assert !(lib.hasInfix "cpamp_" unit.serviceConfig.ExecStart);
assert builtins.elem "cpa-manager-plus.service" hades.dotfiles.labUpdate.requiredUnits;
assert !(builtins.elem 18317 hades.networking.firewall.allowedTCPPorts);
true
