{
  name = "jio-service";
  platforms = [ "darwin" "nixos" ];
  requires = [ "jio" ];
  nixosHome = [ ./home-nixos.nix ];
  darwinHome = [ ./home-darwin.nix ];
}
