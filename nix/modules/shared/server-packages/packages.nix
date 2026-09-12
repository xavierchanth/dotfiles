{lib, pkgs, ...}: {
  home.packages = (with pkgs; [
    bash
    zsh
    spaceship-prompt

    coreutils
    moreutils
    curl
    vim
    neovim
    stow
    tmux
    tree
    unzip
    wget

    bind
    iperf3
    lsof
    nettools
    nmap
    openssl

    less
    bat
    fd
    fzf
    ripgrep
    just
    jq

    git
    difftastic
    jujutsu
  ])
  ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin (with pkgs; [
    iproute2mac
  ])
  ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux (with pkgs; [
    iproute2
    traceroute
  ]);
}
