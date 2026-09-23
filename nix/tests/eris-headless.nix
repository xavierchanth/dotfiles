{ lib, mkDarwin }:
let
  eris = (mkDarwin "eris").config;
  sshConfig = eris.services.openssh.extraConfig;
  authorizedKeys = eris.users.users.chant.openssh.authorizedKeys.keys;
in
assert eris.services.openssh.enable;
assert lib.hasInfix "AllowUsers chant" sshConfig;
assert lib.hasInfix "AuthenticationMethods publickey" sshConfig;
assert lib.hasInfix "PasswordAuthentication no" sshConfig;
assert lib.hasInfix "KbdInteractiveAuthentication no" sshConfig;
assert lib.hasInfix "PermitRootLogin no" sshConfig;
assert lib.hasInfix "PermitEmptyPasswords no" sshConfig;
assert authorizedKeys == [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGjNyTPVTrUJcWrox+nheN7oEOYejfIrwcLgTac/qdNy xavierchanth nyx"
];
assert eris.services.tailscale.enable;
assert !eris.services.tailscale.overrideLocalDns;
assert eris.launchd.daemons.tailscaled.serviceConfig.Label == "com.tailscale.tailscaled";
assert eris.launchd.daemons.tailscaled.serviceConfig.RunAtLoad;
assert eris.power.restartAfterPowerFailure;
assert eris.power.restartAfterFreeze;
assert lib.hasInfix "/usr/bin/pmset -a sleep 0 standby 0 autopoweroff 0 powernap 0" eris.system.activationScripts.noSleep.text;
assert eris.system.defaults.loginwindow.autoLoginUser == null;
true
