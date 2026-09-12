{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.xmt.packages.${pkgs.system}.default ];
}
