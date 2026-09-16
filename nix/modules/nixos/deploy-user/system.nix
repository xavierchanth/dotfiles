{ deployment, lib, ... }: let
  keyOptions = "no-agent-forwarding,no-port-forwarding,no-X11-forwarding,no-user-rc";
in {
  users.users.${deployment.user} = {
    isNormalUser = true;
    description = "Dotfiles deployment operator";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = map (key: "${keyOptions} ${key}") deployment.authorizedKeys;
  };

  services.openssh.extraConfig = lib.mkAfter ''
    Match User ${deployment.user}
      AllowAgentForwarding no
      AllowTcpForwarding no
      X11Forwarding no
      PermitUserRC no
    Match all
  '';
}
