{
  name = "cage-desktop";
  platforms = [ "nixos" ];
  requires = [ "mise-workstation" ];
  nixos = [ ./system.nix ];
  home = [ ./home.nix ];
}
