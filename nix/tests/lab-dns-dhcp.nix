{ lib, mkNixos, contextFor }:
let
  hades = (mkNixos "hades").config;
  cfg = hades.dotfiles.labDnsDhcp;
  service = hades.systemd.services.lab-dns-dhcp;
  prepare = service.serviceConfig.ExecStartPre;
  authorityPackage = lib.findSingle (package: lib.getName package == "lab-dhcp-authority") null null hades.environment.systemPackages;
  firewall = hades.networking.firewall.interfaces.enp1s0 or { };
in
assert builtins.elem "lab-dns-dhcp" (contextFor "hades").groupNames;
assert !cfg.enable;
assert !cfg.dhcpFirewallEnable;
assert cfg.address == "192.168.17.2" && cfg.router == "192.168.17.1";
assert cfg.poolStart == "192.168.17.100" && cfg.poolEnd == "192.168.17.199";
assert cfg.leaseSeconds == 43200;
assert cfg.privateOverlayFile == "/var/lib/lab-dns-dhcp/private-reservations.json";
assert cfg.authorityFile == "/var/lib/lab-dns-dhcp/dhcp-authority.json";
assert builtins.attrNames cfg.reservations == [ "eris" "hades" "poseidon" "zeus" ];
assert cfg.records."eris.lab.xavierchanth.xyz" == "192.168.17.5";
assert !(cfg.records ? "lab.xavierchanth.xyz");
assert !(cfg.records ? "executor.lab.xavierchanth.xyz");
assert lib.hasInfix "lab-dns-dhcp-prepare" prepare;
assert authorityPackage != null;
assert lib.hasInfix "lab-dhcp-authority-watchdog" hades.systemd.services.lab-dhcp-authority-watchdog.serviceConfig.ExecStart;
assert service.serviceConfig.StateDirectoryMode == "0700";
assert !(builtins.elem 53 (firewall.allowedTCPPorts or [ ]));
assert !(builtins.elem 53 (firewall.allowedUDPPorts or [ ]));
assert !(builtins.elem 67 (firewall.allowedUDPPorts or [ ]));
assert !(builtins.elem 67 hades.networking.firewall.allowedUDPPorts);
assert hades.systemd.timers.lab-dhcp-authority-watchdog.timerConfig.OnUnitActiveSec == "30s";
assert hades.systemd.timers.lab-dhcp-authority-watchdog.timerConfig.OnBootSec == "30s";
assert hades.systemd.timers.lab-dhcp-authority-watchdog.wantedBy == [ ];
assert !(builtins.elem "lab-dns-dhcp.service" hades.dotfiles.labUpdate.requiredUnits);
assert service.wantedBy == [ ];
true
