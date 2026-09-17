{
  name = "cpa-manager-plus";
  platforms = [ "nixos" ];
  requires = [ "cliproxyapi" ];
  nixos = [ ./system.nix ];
}
