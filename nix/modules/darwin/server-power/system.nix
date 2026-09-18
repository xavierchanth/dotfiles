{ lib, ... }:
{
  power = {
    restartAfterPowerFailure = true;
    restartAfterFreeze = true;
  };

  system.activationScripts.noSleep.text = lib.mkAfter ''
    echo >&2 "Disabling automatic system sleep..."
    /usr/bin/pmset -a sleep 0 standby 0 autopoweroff 0 powernap 0
  '';
}
