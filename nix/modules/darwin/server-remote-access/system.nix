{ ... }: {
  # nix-darwin manages Apple's built-in sshd and the open-source tailscaled
  # LaunchDaemon; neither depends on a graphical login session.
  services.openssh = {
    enable = true;
    extraConfig = ''
      PubkeyAuthentication yes
      AuthenticationMethods publickey
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
    '';
  };
  services.tailscale = {
    enable = true;
    overrideLocalDns = false;
  };
}
