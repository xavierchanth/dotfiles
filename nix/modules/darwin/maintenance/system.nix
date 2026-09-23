{ lib, pkgs, ... }: let
  maintenance = pkgs.writeShellApplication {
    name = "nix-store-maintenance";
    runtimeInputs = [ pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.nix ];
    text = builtins.readFile ../../../../scripts/nix-store-maintenance.sh;
  };
in {
  environment.systemPackages = [ maintenance ];

  system.activationScripts.postActivation.text = lib.mkAfter ''
    ${maintenance}/bin/nix-store-maintenance request
  '';

  launchd.daemons.dotfiles-nix-store-maintenance.serviceConfig = {
    ProgramArguments = [ "${maintenance}/bin/nix-store-maintenance" "run" ];
    StartCalendarInterval = map (Hour: { inherit Hour; Minute = 0; }) [ 4 5 6 ];
    ProcessType = "Background";
    LowPriorityIO = true;
    LowPriorityBackgroundIO = true;
  };
}
