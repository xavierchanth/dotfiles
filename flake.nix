{
  description = "Cross-platform-ready dotfiles flake with nix-darwin and Home Manager";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = { url = "github:nix-darwin/nix-darwin/master"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = { url = "github:homebrew/homebrew-core"; flake = false; };
    homebrew-cask = { url = "github:homebrew/homebrew-cask"; flake = false; };
    homebrew-rwx = { url = "github:rwx-cloud/homebrew-tap"; flake = false; };
    home-manager = { url = "github:nix-community/home-manager/master"; inputs.nixpkgs.follows = "nixpkgs"; };
    deploy-rs = { url = "github:serokell/deploy-rs"; inputs.nixpkgs.follows = "nixpkgs"; };
    xmt.url = "github:xavierchanth/xmt";
    jio.url = "github:chanthavong-consulting/jio";
  };
  outputs = inputs: import ./nix { inherit inputs; };
}
