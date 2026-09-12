{
  name = "jio";
  platforms = [ "darwin" "nixos" ];
  requires = [ "mise-workstation" ];
  home = [ ./home.nix ];
  nixos = [ ./system.nix ];
  darwin = [ ./system.nix ];
}
