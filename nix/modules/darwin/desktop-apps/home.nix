{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.xmt.packages.${pkgs.stdenv.hostPlatform.system}.default ];
}
