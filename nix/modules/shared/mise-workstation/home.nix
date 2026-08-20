{config, lib, pkgs, ...}: let
  consumeCredential = pkgs.writeShellApplication {
    name = "consume-deploy-credential";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ../../../../scripts/consume-deploy-credential;
  };
  activationPackages = with pkgs; [
    bash
    cacert
    coreutils
    curl
    diffutils
    file
    findutils
    gawk
    git
    gnugrep
    gnupg
    gnused
    gnutar
    gzip
    openssh
    patch
    perl
    unzip
    wget
    which
    xz
  ] ++ lib.optionals pkgs.stdenv.isLinux (with pkgs; [
    gnumake
    pkg-config
    python3
    stdenv.cc
  ]);
in {
  # Mise belongs to every coding workstation. Linux also needs the native
  # linker/compiler and pkg-config for cargo-installed tools; avoid shadowing
  # Darwin's toolchain.
  home.packages = [ pkgs.mise ] ++ lib.optionals pkgs.stdenv.isLinux [ pkgs.stdenv.cc pkgs.pkg-config ];
  # Stow owns the global config and lockfile, so installation must run after
  # stowDotfiles. Trust only this repository-managed global configuration.
  # Keep activation dependencies and secrets scoped to this subshell.
  home.activation.installMiseTools = lib.hm.dag.entryAfter ["stowDotfiles"] ''
    (
      export HOME=${lib.escapeShellArg config.home.homeDirectory}
      export MISE_GLOBAL_CONFIG_FILE="$HOME/.config/mise/config.toml"
      export MISE_YES=1
      export PATH=${lib.escapeShellArg (lib.makeBinPath activationPackages)}:"$PATH"
      export SSL_CERT_FILE=${lib.escapeShellArg "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"}
      export NIX_SSL_CERT_FILE="$SSL_CERT_FILE"
      ${pkgs.mise}/bin/mise trust "$MISE_GLOBAL_CONFIG_FILE"
      set +x
      github_token="$(${consumeCredential}/bin/consume-deploy-credential github-api 2>/dev/null || true)"
      if [[ -z $github_token ]]; then
        github_token="$(${pkgs.coreutils}/bin/timeout 5s ${pkgs.gh}/bin/gh auth token 2>/dev/null || true)"
      fi
      if [[ -n $github_token ]]; then export MISE_GITHUB_TOKEN="$github_token"; fi
      unset github_token
      ${pkgs.mise}/bin/mise install
    )
  '';
}
