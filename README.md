# dotfiles

This branch is the `v2` rewrite of the dotfiles repository. It keeps the setup
in the same repo as `v1`, but reorganizes the system around a Nix flake with
`nix-darwin`, Home Manager, and a small Stow layer for tool configs that still
fit best as tracked dotfiles.

## Layout

- `flake.nix`: thin flake entrypoint and inputs; `nix/default.nix` constructs outputs from `nix/inventory.nix`.
- `justfile`: discoverable front doors that delegate to packaged apps and existing scripts.
- `nix/hosts/{darwin,nixos}/<hostname>`: host-specific system configuration.
- `nix/home/chant`: Home Manager user configuration.
- `nix/modules/shared`: shared modules for packages and shell tooling.
- `nix/modules/darwin`: macOS-specific modules such as defaults, Homebrew, and
  input tooling.
- `stow`: application configs that are linked into place during Home Manager
  activation.
- `bin`: shared and host-specific commands installed on the user PATH.
- `scripts`: repository-local maintenance and deployment entrypoints.
- `docs`: operational notes for lab hosts, strategy, and peer caching.
- `tests`: shell-based regression tests for repository scripts.

## What This Config Manages

See the [machine inventory](docs/hosts.md) for all machines and their assigned
roles, including unmanaged Windows hosts. The [lab strategy](docs/lab/strategy.md)
and [shared Docker plan](docs/lab/docker.md) describe execution and service placement.
See [Jio configuration](docs/jio.md) for private package fetching and personal agent setup.

- System configuration with `nix-darwin`
- User environment with Home Manager
- Homebrew taps and casks through Nix-managed Homebrew integration
- Tool configs for Git, Zsh, tmux, Neovim, Zed, Ghostty, JJ, and Kanata

## Apply The Configuration

On a configured host, build and switch the matching darwin configuration with:

```bash
darwin-rebuild switch --flake .#nyx
# or
darwin-rebuild switch --flake .#eris
```

The host config also expects Rosetta to be installed on Apple Silicon before or
alongside the first switch:

```bash
softwareupdate --install-rosetta --agree-to-license
```

Routine lab deployment has one portable entrypoint:

```bash
nix run .#deploy -- hades
nix run .#deploy -- lab
# or: just deploy-host hades
```

See [`docs/lab/deploy.md`](docs/lab/deploy.md) before deployment. The assured Hades path and attended OpenWrt path intentionally remain separate.

If you only want to evaluate the Home Manager profile, this flake also exposes:

```bash
home-manager switch --flake .#chant@nyx
# or
home-manager switch --flake .#chant@eris
```

## Notes

This repo is the source of truth for the new migration work. The `v1` branch is
still useful as historical reference, but changes for the new setup should land
here unless there is a specific reason to backport them.
