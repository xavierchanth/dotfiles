{
  name = "executor";
  platforms = [ "nixos" ];
  requires = [ "podman-host" ];
  nixos = [ ./system.nix ];
}
