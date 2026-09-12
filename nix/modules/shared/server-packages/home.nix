{config, lib, pkgs, ...}: {
  imports = [
    ./packages.nix
  ];

  # Workstation activation created these links imperatively. Remove only links
  # owned by Home Manager; leave regular files and user data untouched.
  home.activation.removeWorkstationApplicationLinks = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (lib.hm.dag.entryAfter ["linkGeneration"] ''
    apps_dir="${config.home.homeDirectory}/Applications"
    hm_apps_dir="$apps_dir/Home Manager Apps"

    [ -d "$apps_dir" ] || exit 0
    find "$apps_dir" -maxdepth 1 -type l | while read -r app_link; do
      target="$(readlink "$app_link" || true)"
      case "$target" in
        /nix/store/*|"$hm_apps_dir"/*) rm -f "$app_link" ;;
      esac
    done
  '');
}
