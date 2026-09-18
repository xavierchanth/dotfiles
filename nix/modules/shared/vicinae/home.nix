{
  inputs,
  lib,
  pkgs,
  ...
}: let
  package = pkgs.callPackage ./package-darwin.nix {};
  packaged = import ./extensions.nix {inherit inputs lib pkgs;};
in {
  imports = [inputs.vicinae.homeManagerModules.default];

  # The extension was originally deployed as an unversioned Stow directory.
  # Remove that legacy copy only when it is byte-for-byte identical to the
  # canonical Nix package; preserve divergent local work for manual review.
  home.activation.removeLegacyVicinaeWindowManagement = lib.hm.dag.entryBefore ["linkGeneration"] ''
    legacy="$HOME/.local/share/vicinae/extensions/window-management"
    canonical="${packaged.extensions.window-management}"
    if [ -d "$legacy" ] && [ ! -L "$legacy" ]; then
      if ${pkgs.diffutils}/bin/diff -qr "$legacy" "$canonical" >/dev/null; then
        $DRY_RUN_CMD rm -rf -- "$legacy"
      else
        echo "Keeping divergent legacy Vicinae window-management extension at $legacy" >&2
      fi
    fi
  '';

  # The signed upstream build registers itself with SMAppService once unless
  # this marker exists. nix-darwin owns the direct launchd job instead so it
  # can supply the declarative settings override without a shell wrapper.
  home.file.".local/state/vicinae/login-item-registered".text = "";

  programs.vicinae = {
    enable = true;
    inherit package;
    enableNumen = false;
    enableSoulver = false;
    enableChromeIntegration = false;
    enableFirefoxIntegration = false;
    launchd.enable = false;
    extensions = builtins.attrValues packaged.extensions;
    settings = lib.recursiveUpdate (import ./settings.nix) {
      providers.keepassxc.preferences = {
        credentialMode = "password";
        expiryMinutes = "5";
      };
    };
  };
}
