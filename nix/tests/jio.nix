{ lib, mkHome, home-manager, jioPackageFor, pkgsFor }: let
  hosts = [ "nyx" "eris" "hades" "poseidon" "zeus" ];
  home = name: (mkHome name).config;
  names = name: map lib.getName (home name).home.packages;
  fixture = system: service: let pkgs = pkgsFor system; in
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit jioPackageFor; };
      modules = [ ../modules/shared/jio/home.nix {
        home.username = "jio-fixture";
        home.homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/jio-fixture" else "/home/jio-fixture";
        home.stateVersion = "25.05";
      } ] ++ lib.optionals service [
        (if pkgs.stdenv.hostPlatform.isDarwin then ../modules/shared/jio-service/home-darwin.nix else ../modules/shared/jio-service/home-nixos.nix)
        { dotfiles.jio.projects = [{ id = "fixture"; upstream = "https://github.com/example/project.git"; default_branch = "main"; account_group = "personal"; availability = "all-personal-machines"; }]; }
      ];
    }).config;
  defaults = fixture "aarch64-darwin" false;
  darwinService = fixture "aarch64-darwin" true;
  linuxService = fixture "x86_64-linux" true;
in assert lib.all (name: builtins.elem "jio" (names name) && builtins.elem "gh" (names name) && builtins.elem "mise" (names name)) hosts;
   assert lib.all (name: (home name).xdg.configFile ? "jio/config.toml" && (home name).xdg.configFile ? "jio/projects.toml") hosts;
   assert defaults.dotfiles.jio.settings.signing.policy == "required";
   assert defaults.dotfiles.jio.projects == [];
   assert (defaults.launchd.agents.jio or null) == null;
   assert darwinService.dotfiles.jio.projects != [] && linuxService.dotfiles.jio.projects != [];
   assert darwinService.launchd.agents.jio.config.ProgramArguments == [ "${darwinService.dotfiles.jio.command}/bin/jio" "serve" ];
   assert linuxService.systemd.user.services.jio.Service.ExecStart == [ "${linuxService.dotfiles.jio.command}/bin/jio serve" ];
   true
