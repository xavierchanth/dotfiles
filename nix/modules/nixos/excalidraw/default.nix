{
  name = "excalidraw";
  platforms = [ "nixos" ];
  requires = [ "podman-host" ];
  nixos = [ ./system.nix ];
}
