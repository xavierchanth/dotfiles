{ config, ... }: {
  systemd.user.services.jio = {
    Unit = {
      Description = "Jio personal node";
      After = [ "dbus.service" ];
    };
    Service = {
      ExecStart = "${config.dotfiles.jio.command}/bin/jio serve";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
