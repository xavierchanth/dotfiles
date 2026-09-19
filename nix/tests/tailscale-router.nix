{ lib, mkNixos }:
let
  hades = (mkNixos "hades").config;
  poseidon = (mkNixos "poseidon").config;
  zeus = (mkNixos "zeus").config;
  flags = hades.services.tailscale.extraSetFlags;
  policy = builtins.fromJSON (builtins.readFile ../../docs/lab/tailscale-policy-fragment.json);
in
assert hades.services.tailscale.useRoutingFeatures == "server";
assert builtins.sort builtins.lessThan flags == builtins.sort builtins.lessThan [
  "--accept-dns=false"
  "--accept-routes=false"
  "--advertise-exit-node"
  "--advertise-routes=192.168.8.0/24"
  "--advertise-tags=tag:lab-host"
  "--exit-node="
  "--exit-node-allow-lan-access=false"
  "--ssh"
];
assert hades.boot.kernel.sysctl."net.ipv4.conf.all.forwarding";
assert hades.boot.kernel.sysctl."net.ipv6.conf.all.forwarding";
assert !(builtins.elem "--accept-routes" flags);
assert !(lib.any (lib.hasPrefix "--snat-subnet-routes=false") flags);
assert !(lib.any (flag: lib.hasPrefix "--exit-node=" flag && flag != "--exit-node=") flags);
assert poseidon.services.tailscale.useRoutingFeatures == "none";
assert zeus.services.tailscale.useRoutingFeatures == "none";
assert policy.hosts.home-lan == "192.168.8.0/24";
assert policy.tagOwners."tag:lab-host" == [ "autogroup:owner" ];
assert policy.autoApprovers.routes."192.168.8.0/24" == [ "tag:lab-host" ];
assert policy.autoApprovers.exitNode == [ "tag:lab-host" ];
assert policy.autoApprovers.services."svc:lab" == [ "tag:lab-host" ];
assert builtins.length policy.grants == 4;
assert builtins.elem {
  src = [ "autogroup:owner" ];
  dst = [ "home-lan" ];
  via = [ "tag:lab-host" ];
  ip = [ "*" ];
} policy.grants;
assert builtins.elem {
  src = [ "autogroup:owner" ];
  dst = [ "autogroup:internet" ];
  via = [ "tag:lab-host" ];
  ip = [ "*" ];
} policy.grants;
assert builtins.elem {
  src = [ "autogroup:owner" ];
  dst = [ "svc:lab" ];
  ip = [ "tcp:443" ];
} policy.grants;
assert policy.ssh == [{
  action = "accept";
  src = [ "autogroup:owner" ];
  dst = [ "tag:lab-host" ];
  users = [ "chant" ];
}];
true
