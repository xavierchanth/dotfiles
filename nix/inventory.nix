let lab = import ./lab.nix; in {
  nyx = { system = "aarch64-darwin"; kind = "darwin"; profile = "darwin-workstation"; };
  eris = {
    system = "aarch64-darwin"; kind = "darwin"; profile = "darwin-server"; lab = lab.hosts.eris;
    deployment = { targetAddress = lab.hosts.eris.address; proxyJump = "hades"; };
  };
  charon = { kind = "openwrt"; profile = "openwrt-router"; lab = lab.hosts.charon; };
  hades = {
    system = "x86_64-linux"; kind = "nixos"; profile = "linux-server"; lab = lab.hosts.hades;
    groups = [ "deploy-user" ]; deployment.useDedicatedUser = false;
    cacheAddress = "hades.xavierchanth.local"; cacheInterface = "enp1s0";
    cacheKeyVersion = "v1"; cachePublicKey = null;
  };
  poseidon = {
    system = "x86_64-linux"; kind = "nixos"; profile = "linux-server"; lab = lab.hosts.poseidon;
    groups = [ "deploy-user" ]; deployment.useDedicatedUser = false;
    cacheAddress = "poseidon.xavierchanth.local"; cacheInterface = "enp1s0";
    cacheKeyVersion = "v1"; cachePublicKey = null;
  };
  zeus = {
    system = "x86_64-linux"; kind = "nixos"; profile = "linux-server"; lab = lab.hosts.zeus;
    groups = [ "deploy-user" ]; deployment.useDedicatedUser = false;
    cacheAddress = "zeus.xavierchanth.local"; cacheInterface = "enp1s0";
    cacheKeyVersion = "v1"; cachePublicKey = null;
  };
}
