{
  name = "homepage";
  platforms = [ "nixos" ];
  requires = [ "docker-host" ];
  nixos = [ ./system.nix ];
}
