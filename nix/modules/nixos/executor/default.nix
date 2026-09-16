{
  name = "executor";
  platforms = [ "nixos" ];
  requires = [ "docker-host" ];
  nixos = [ ./system.nix ];
}
