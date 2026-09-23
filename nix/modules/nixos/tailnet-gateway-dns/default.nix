{
  name = "tailnet-gateway-dns";
  platforms = [ "nixos" ];
  requires = [ "tailscale" "service-gateway" ];
  nixos = [ ./system.nix ];
}
