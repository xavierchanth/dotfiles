{ pkgs, ... }: {
  hardware.graphics.enable = true;
  programs.firefox.enable = true;
  programs.xwayland.enable = true;
  users.users.computer = {
    isNormalUser = true;
    description = "Computer Use";
  };
  environment.systemPackages = [
    (import ./package.nix { inherit pkgs; })
    (import ./mcp-package.nix { inherit pkgs; })
    pkgs.cage
    pkgs.wayvnc
    pkgs.grim
    pkgs.wtype
    pkgs.python3Packages.vncdotool
  ];
}
