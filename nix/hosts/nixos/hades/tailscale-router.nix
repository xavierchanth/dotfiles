{ ... }:
{
  services.tailscale = {
    useRoutingFeatures = "server";
    extraSetFlags = [
      "--accept-routes=false"
      "--advertise-exit-node"
      "--advertise-routes=192.168.8.0/24"
      "--advertise-tags=tag:lab-host"
      "--exit-node="
      "--exit-node-allow-lan-access=false"
      "--ssh"
    ];
  };
}
