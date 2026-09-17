{
  name = "plane";
  platforms = [ "nixos" ];
  requires = [ "docker-host" ];
  nixos = [ ./system.nix ];
}
