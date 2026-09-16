{lib, ...}: let
  selection = builtins.fromJSON (builtins.readFile ../../../../themes/selection.json);
in {
  programs.ghostty = {
    enable = true;
    package = null;
    enableZshIntegration = false;

    settings = {
      theme = "light:${selection.light},dark:${selection.dark}";

      font-family = "CommitMono Nerd Font";
      font-feature = "+cv07,+ss03,+ss04,+ss05";
      font-size = 13;
      adjust-cell-height = "20%";

      window-padding-balance = true;
      background-opacity = 0.95;
      background-blur-radius = 20;

      confirm-close-surface = false;
      quit-after-last-window-closed = true;
      link-url = true;
      app-notifications = "no-clipboard-copy";

      mouse-hide-while-typing = true;
      mouse-shift-capture = false;

      # Keybinds
      macos-option-as-alt = true;
      keybind = [
        "ctrl+shift+t=unbind"
        "super+r=reload_config"
        "super+j=text:5j"
        "super+k=text:5k"

        "super+physical:one=text:\\x001"
        "super+physical:two=text:\\x002"
        "super+physical:three=text:\\x003"
        "super+physical:four=text:\\x004"
        "super+physical:five=text:\\x005"
        "super+physical:six=text:\\x006"
        "super+physical:seven=text:\\x007"
        "super+physical:eight=text:\\x008"
        "super+physical:nine=text:\\x009"

        "super+ctrl+alt+shift+a=text:\\x00a"
        "super+ctrl+alt+shift+s=text:\\x00s"
        "super+ctrl+alt+shift+d=text:\\x00d"
        "super+ctrl+alt+shift+r=text:\\x00r"
        "super+ctrl+alt+shift+c=text:\\x00c"
        "super+ctrl+alt+shift+p=text:\\x00p"
        "super+ctrl+alt+shift+l=text:\\x00l"
        "super+ctrl+alt+shift+v=text:\\x00v"
        "super+ctrl+alt+shift+x=text:\\x00x"
        "super+ctrl+alt+shift+w=text:\\x00w"
        "super+ctrl+alt+shift+z=text:\\x00z"
        "super+ctrl+alt+shift+f=text:\\x00f"
        "super+ctrl+alt+shift+g=text:\\x00g"
        "super+ctrl+alt+shift+n=text:\\x00n"
        "super+ctrl+alt+shift+e=text:\\x00e"

        "super+ctrl+shift+alt+q=text:\\x00d"
      ];
    };
  };

  programs.zsh.initContent = lib.mkOrder 1100 ''
    if [[ $TERM_PROGRAM == ghostty &&
          -r "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration" ]]; then
      source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
    fi
  '';
}
