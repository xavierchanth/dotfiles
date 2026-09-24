# AGENTS.md

This repository is a new port of the dotfiles setup. Treat it as the source of truth.

## Working Rules

- Be direct and prefer stating the positive. Avoid negative framing unless it clarifies a real boundary.
- Prefer adapting and extending the configuration in this repo instead of assuming the old setup should be copied over.
- When configuring tools, it can sometimes be helpful to reference the `v1` branch in this repo as historical context.
- Always ask the user before pulling, copying, or otherwise using config from the `v1` branch.
- Keep changes aligned with the current Nix-based structure unless the user asks for a broader redesign.
- Prefer reproducible, cross-machine configuration. Do not hardcode machine-specific paths, usernames, home directories, or profile locations when a Nix value can derive them.
- When a path depends on a package or system context, derive it from Nix instead of spelling it literally. Example: prefer `${pkgs.tmux}/bin/tmux` or `${config.home.homeDirectory}` over hardcoded paths like `/etc/profiles/per-user/chant/bin/tmux` or `/Users/chant/...`.

## Tailscale Administration

Prefer normal interactive Tailscale sign-in and manual admin-console changes for tailnet-wide configuration, including device tags, service definitions and approvals, DNS settings, and access policy. Dotfiles may declaratively configure each machine's local Tailscale client and the services it advertises. Introduce OAuth credentials or automated tailnet-wide mutations only when Xavier explicitly approves automation for a specific recurring need.

## Repo Shape

- `flake.nix` and `flake.lock`: thin flake entrypoint and pinned inputs.
- `justfile`: root operator shortcuts; recipes delegate to canonical flake apps/scripts.
- `nix/default.nix` and `nix/inventory.nix`: flake outputs and canonical host inventory.
- `nix/profiles.nix` and `nix/registry.nix`: explicit profile composition and typed group descriptors.
- `nix/lib/*`: pure group resolution and Stow helpers.
- `nix/hosts/{darwin,nixos}/*`: host-specific system configuration.
- `nix/home/chant/default.nix`: Home Manager user configuration.
- `nix/modules/{shared,home,darwin,nixos}/*`: reusable platform and user modules.
- `scripts/*.sh` and `scripts/deploy`: repository-local maintenance and the packaged deploy-rs wrapper.
- `bin/shared` and `bin/hosts/*`: commands intended for the configured user PATH.
- `packages/<ecosystem>/<name>`: standalone source packages grouped by ecosystem; see `docs/repository-layout.md`.
- `docs/lab/*`: lab architecture and operational runbooks.
- `tests/*`: repository script regression tests.

## Change Approach

- Make focused edits that match the existing module layout.
- Put standalone source projects in `packages/<ecosystem>/<name>`; reserve `stow/` for files linked into a user environment.
- Prefer adding or updating the relevant shared or host module over introducing ad hoc files.
- If a tool is not configured yet and the `v1` branch may be useful as reference, pause and ask first.
