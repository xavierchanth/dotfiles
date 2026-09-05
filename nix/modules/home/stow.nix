{config, hostProfile, lib, pkgs, resolvedGroups, ...}: let
  home = config.home.homeDirectory;
  selected = name: lib.any (item: item.name == name) resolvedGroups.stow;
  commands = import ../../lib/stow.nix { inherit lib pkgs; } {
    inherit home;
    declarations = resolvedGroups.stow;
  };
  inherit (commands) mkdirCommands stowCommands;
in {
  home.extraDependencies = lib.optional (selected "agents")
    (import ../../handoff-reference-package.nix { inherit pkgs; });

  home.activation.stowDotfiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
    STOW_DIR="${home}/.dotfiles/stow"
    ${mkdirCommands}

    # Kanata is no longer managed. Remove only the stale Stow-owned link,
    # preserving any replacement file the user may have created.
    stale_kanata="${home}/.config/kanata/macos.kbd"
    if [ -L "$stale_kanata" ]; then
      case "$(readlink "$stale_kanata" || true)" in
        */stow/kanata/macos.kbd) rm -f "$stale_kanata" ;;
      esac
    fi

    ${lib.optionalString (selected "ghostty-themes") ''
      # Ordered migration: old Home Manager Ghostty theme links must be removed
      # before Stow can own the same paths.
      ghostty_theme_dir="${home}/.config/ghostty/themes"
      mkdir -p "$ghostty_theme_dir"
      for theme in "$ghostty_theme_dir"/*; do
        [ -L "$theme" ] || continue
        target="$(readlink "$theme" || true)"
        case "$target" in
          /nix/store/*-home-manager-files/.config/ghostty/themes/*) rm -f "$theme" ;;
        esac
      done
      ${pkgs.stow}/bin/stow --dir="$STOW_DIR" --target="$ghostty_theme_dir" --restow ghostty-themes
    ''}

    ${lib.optionalString (lib.any (name: !(selected name)) [ "cmux" "grok" "mise" "zed" "ghostty-themes" ]) ''
      cleanup_stow_links() {
        package_name="$1"
        target_dir="$2"
        [ -d "$target_dir" ] || return 0

        find "$target_dir" -type l | while read -r link; do
          target="$(readlink "$link" || true)"
          case "$target" in
            "$STOW_DIR/$package_name"/*|*/stow/"$package_name"/*) rm -f "$link" ;;
          esac
        done
      }

      ${lib.optionalString (!(selected "cmux")) ''cleanup_stow_links cmux "${home}/.config/cmux"''}
      cleanup_stow_links grok "${home}/.grok"
      ${lib.optionalString (!(selected "mise")) ''cleanup_stow_links mise "${home}/.config/mise"''}
      ${lib.optionalString (!(selected "zed")) ''cleanup_stow_links zed "${home}/.config/zed"''}
      ${lib.optionalString (!(selected "ghostty-themes")) ''cleanup_stow_links ghostty-themes "${home}/.config/ghostty/themes"''}
    ''}

    ${stowCommands}
  '';
}
