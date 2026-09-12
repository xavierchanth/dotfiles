{ username, ... }: {
  dotfiles.labUpdate.requiredUnits = [ "docker.service" ];

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    # Remote clients reach the Unix socket through SSH over Tailscale.
    listenOptions = [ "/run/docker.sock" ];
    autoPrune.enable = false;
    logDriver = "local";
    daemon.settings = {
      live-restore = true;
      log-opts = {
        max-size = "10m";
        max-file = "3";
      };
      # Published services are private until deliberately exposed or tunneled.
      ip = "127.0.0.1";
      default-network-opts.bridge."com.docker.network.bridge.host_binding_ipv4" = "127.0.0.1";
    };
  };

  # Docker access is host administration; do not grant it to computer-use users.
  users.users.${username}.extraGroups = [ "docker" ];
}
