{lib, ...}: {
  # This public key authenticates private release closures imported with
  # scripts/jio-release. It does not authorize additional substituters/users.
  nix.settings.extra-trusted-public-keys = [
    (lib.removeSuffix "\n" (builtins.readFile ./cache-public-key))
  ];
}
