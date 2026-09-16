let
  descriptor = import ./brew-desktop-apps.nix;
in descriptor // {
  darwinHome = (descriptor.darwinHome or []) ++ [ ./home.nix ];
}
