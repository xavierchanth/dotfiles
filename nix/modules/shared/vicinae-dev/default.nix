{
  name = "vicinae-dev";
  platforms = ["darwin"];
  requires = ["vicinae"];
  home = [./home.nix];
  stow = [{
    name = "vicinae-window-management";
    target = ".local/share/vicinae/dev-extensions/window-management";
    prepare = [".local/share/vicinae/dev-extensions/window-management"];
  }];
}
