{ username, ... }: {
  # nix-darwin manages Apple's built-in sshd and the open-source tailscaled
  # LaunchDaemon; neither depends on a graphical login session.
  services.openssh = {
    enable = true;
    extraConfig = ''
      AllowUsers ${username}
      PubkeyAuthentication yes
      AuthenticationMethods publickey
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
      PermitEmptyPasswords no
    '';
  };
  users.users.${username}.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGjNyTPVTrUJcWrox+nheN7oEOYejfIrwcLgTac/qdNy xavierchanth nyx"
  ];
  services.tailscale = {
    enable = true;
    overrideLocalDns = false;
  };
}
