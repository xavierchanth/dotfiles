{ config, ... }: {
  virtualisation = {
    docker.enable = false;
    oci-containers.backend = "podman";
    podman = {
      enable = true;
      autoPrune.enable = false;
      dockerCompat = false;
      dockerSocket.enable = false;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  assertions = [{
    assertion = !config.virtualisation.podman.dockerCompat && !config.virtualisation.podman.dockerSocket.enable;
    message = "Hades uses native Podman interfaces without Docker compatibility";
  }];
}
