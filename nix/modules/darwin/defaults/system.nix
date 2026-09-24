{config, hostname, username, ...}: let
  userHome = config.users.users.${username}.home;
  guiPath = [
    "/run/current-system/sw/bin"
    "/etc/profiles/per-user/${username}/bin"
    "${userHome}/.dotfiles/bin/shared"
    "${userHome}/.dotfiles/bin/hosts/${hostname}"
    "${config.homebrew.prefix}/bin"
    "${config.homebrew.prefix}/sbin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];
in {
  # GUI apps on macOS inherit PATH from the per-user launchd session rather
  # than from interactive shell startup files.
  launchd.user.envVariables.PATH = builtins.concatStringsSep ":" guiPath;

  system.defaults = {
    CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
      # Keyboard Shortcuts > Input Sources:
      # - Select the previous input source (Control-Space)
      # - Select next source in Input menu (Control-Option-Space)
      "60".enabled = false;
      "61".enabled = false;
    };

    CustomUserPreferences."com.apple.Spotlight" = {
      PasteboardHistoryEnabled = false;
      orderedItems = [
        {
          enabled = false;
          name = "CONTACT";
        }
        {
          enabled = false;
          name = "MENU_SPOTLIGHT_SUGGESTIONS";
        }
      ];
    };

    NSGlobalDomain = {
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
    };

    dock = {
      autohide = true;
      expose-group-apps = true;
      mru-spaces = false;
      show-recents = false;
      tilesize = 40;
    };

    finder = {
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = false;
      ShowPathbar = true;
      ShowStatusBar = true;
    };

    trackpad = {
      Clicking = true;
    };
  };
}
