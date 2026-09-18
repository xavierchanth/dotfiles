{
  name = "tailnet-gateway-dns";
  platforms = [ "nixos" ];
  requires = [ "tailscale" ];
  nixos = [ ./system.nix ];
}
