{
  inputs,
  lib,
  pkgs,
}: let
  cleanExtensionSource = source:
    lib.cleanSourceWith {
      src = source;
      filter = path: type: let
        name = baseNameOf path;
      in
        !(builtins.elem name [
          "node_modules"
          "dist"
          "build"
          ".raycast"
          "vicinae-env.d.ts"
        ]);
    };

  mkExtension = name:
    inputs.vicinae.lib.${pkgs.stdenv.hostPlatform.system}.mkVicinaeExtension {
      pname = name;
      version = "0.1.0";
      src = cleanExtensionSource ../../../../packages/vicinae/${name};
    };

  # The KeePassXC cask links its CLI into Homebrew's architecture-specific
  # prefix. Prefer that stable integration point over reaching into the app
  # bundle, while retaining an exact executable path for shell-free spawning.
  brewPrefix =
    if pkgs.stdenv.hostPlatform.isAarch64
    then "/opt/homebrew"
    else "/usr/local";
  keepassxcCli = "${brewPrefix}/bin/keepassxc-cli";
  keychainHelper = pkgs.stdenv.mkDerivation {
    pname = "vicinae-keepassxc-keychain-helper";
    version = "0.1.0";
    src = ../../../../packages/vicinae/keepassxc/native/keychain-helper.swift;
    dontUnpack = true;
    nativeBuildInputs = [pkgs.swift];
    buildPhase = ''
      runHook preBuild
      substitute "$src" keychain-helper.swift \
        --replace-fail '@KEEPASSXC_CLI@' '${keepassxcCli}'
      swiftc -O -framework LocalAuthentication -framework Security keychain-helper.swift -o vicinae-keepassxc-keychain-helper
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 vicinae-keepassxc-keychain-helper "$out/bin/vicinae-keepassxc-keychain-helper"
      runHook postInstall
    '';
    meta.platforms = lib.platforms.darwin;
  };
in {
  extensions = {
    window-management = mkExtension "window-management";
    keepassxc = mkExtension "keepassxc";
  };

  inherit keepassxcCli keychainHelper;
}
