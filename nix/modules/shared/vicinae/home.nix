{
  inputs,
  lib,
  pkgs,
  ...
}: let
  package = pkgs.callPackage ./package-darwin.nix {};
  windowManagement = import ./extensions.nix {inherit inputs lib pkgs;};
in {
  imports = [inputs.vicinae.homeManagerModules.default];

  # The signed upstream build registers itself with SMAppService once unless
  # this marker exists. nix-darwin owns the direct launchd job instead so it
  # can supply the declarative settings override without a shell wrapper.
  home.file.".local/state/vicinae/login-item-registered".text = "";

  programs.vicinae = {
    enable = true;
    inherit package;
    enableNumen = false;
    enableSoulver = false;
    enableChromeIntegration = false;
    enableFirefoxIntegration = false;
    launchd.enable = false;
    extensions = [windowManagement];
    settings = import ./settings.nix;
  };
}
