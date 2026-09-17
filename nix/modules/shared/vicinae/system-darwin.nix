{pkgs, ...}: let
  package = pkgs.callPackage ./package-darwin.nix {};
  settingsFile = (pkgs.formats.json {}).generate "vicinae-settings.json" (import ./settings.nix);
in {
  nix.settings = {
    extra-substituters = ["https://vicinae.cachix.org"];
    extra-trusted-public-keys = ["vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="];
  };

  environment.systemPackages = [package];

  launchd.user.agents.vicinae.serviceConfig = {
    ProgramArguments = [
      "${package}/Applications/Vicinae.app/Contents/MacOS/Vicinae"
      "server"
    ];
    EnvironmentVariables.VICINAE_OVERRIDES = "${settingsFile}";
    RunAtLoad = true;
    KeepAlive = {
      Crashed = true;
      SuccessfulExit = false;
    };
    ProcessType = "Interactive";
  };
}
