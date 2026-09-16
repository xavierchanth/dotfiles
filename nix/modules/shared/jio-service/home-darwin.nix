{ config, ... }: {
  launchd.agents.jio = {
    enable = true;
    config = {
      ProgramArguments = [ "${config.dotfiles.jio.command}/bin/jio" "serve" ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      ThrottleInterval = 5;
      Umask = 63;
    };
  };
}
