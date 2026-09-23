{
  name = "homepage";
  platforms = [ "nixos" ];
  requires = [ "podman-host" ];
  nixos = [ ./system.nix ];
}
