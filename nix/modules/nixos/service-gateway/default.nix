{
  name = "service-gateway";
  platforms = [ "nixos" ];
  requires = [ "tailscale" ];
  nixos = [ ./system.nix ];
}
