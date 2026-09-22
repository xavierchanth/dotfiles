{ lib, mkNixos }:
let
  hades = (mkNixos "hades").config;
  poseidon = (mkNixos "poseidon").config;
  zeus = (mkNixos "zeus").config;
  flags = hades.services.tailscale.extraSetFlags;
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
true
