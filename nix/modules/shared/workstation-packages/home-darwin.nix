{config, lib, pkgs, ...}: {
  imports = [
    ../../home/darwin-applications.nix
    ../packages.nix
  ];

  # Android Studio owns this SDK; unlike developer runtimes it is not managed
  # by mise. This module is imported only by Darwin workstation configurations.
  home.sessionVariables = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    ANDROID_HOME = "${config.home.homeDirectory}/Library/Android/sdk";
  };
  home.sessionPath = lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    "${config.home.homeDirectory}/Library/Android/sdk/cmdline-tools/latest/bin"
  ];
}
