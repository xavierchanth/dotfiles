{
  config,
  lib,
  pkgs,
  ...
}: {
  home.file.".bunfig.toml".text = ''
    [install]
    linker = "isolated"
    globalStore = true
  '';

  home.file.".cargo/config.toml".text = ''
    [build]
    jobs = 4
    rustc-wrapper = "sccache"
    incremental = false
  '';

  home.packages =
    (with pkgs; [
      # Shell
      bash
      zsh
      spaceship-prompt

      # Core Utilities
      coreutils
      moreutils
      fastfetch
      curl
      vim
      parallel
      stow
      tmux
      tree
      # unar
      unzip
      wget

      # Networking tools
      bind
      iperf3
      lsof
      nettools
      nmap
      openssl

      # Pagers
      less
      bat
      bat-extras.batdiff
      bat-extras.batgrep
      bat-extras.batman
      bat-extras.batpipe
      bat-extras.batwatch
      bat-extras.prettybat

      # Development
      neovim
      tree-sitter
      fd
      fzf
      ripgrep
      just
      jq

      # Containers
      docker-client
      docker-compose

      # Fonts
      nerd-fonts.commit-mono
      nerd-fonts.jetbrains-mono

      # Git
      git
      difftastic
      jujutsu
      meld

      # File-format based Utilities
      imagemagick
      pandoc
      poppler
      resvg

      # CLI Apps
      yazi

      # Programming Languages
      cmake
      mise
      ninja
      postgresql_16
    ])
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin (with pkgs; [
      # Mac only
      docker-credential-helpers
      iproute2mac
    ])
    ++ lib.optionals (!pkgs.stdenv.hostPlatform.isDarwin) (with pkgs; [
      # Linux
      traceroute
      iproute2
    ]);
}
