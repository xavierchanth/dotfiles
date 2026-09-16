{
  name = "docker-host";
  platforms = [ "nixos" ];
  requires = [ "ssh-server" "tailscale" ];
  nixos = [ ./system.nix ];
}
