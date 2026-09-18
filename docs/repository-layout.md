# Repository layout

This repository separates declarative system configuration, linked dotfiles,
standalone source packages, and operational tooling. Each artifact should have
one canonical source location.

## Canonical directories

- `nix/`: flake composition, host inventory, and reusable NixOS, nix-darwin,
  and Home Manager modules.
- `stow/<name>/`: dotfile packages whose contents are linked into a user's home
  or XDG configuration by GNU Stow.
- `packages/<ecosystem>/<name>/`: independently built or developed source
  packages, grouped by their application or runtime ecosystem.
- `bin/`: commands installed on the configured user PATH.
- `scripts/`: repository maintenance and deployment entrypoints.
- `docs/`: architecture, operations, and repository guidance.
- `tests/`: repository-level regression tests.

## Package placement

Use `packages/<ecosystem>/<name>` when a project has its own build, test, or
development lifecycle. The ecosystem identifies the host application or
runtime, while the name identifies the package within it. For example, the
Vicinae extension source lives at:

```text
packages/vicinae/window-management
```

Keep generated dependencies and build output ignored within each package.
Repository entrypoints should run the canonical package directly rather than a
deployed or linked copy.

Use `stow/<name>` only when the tracked files themselves are intended to be
linked into the user's environment. Stow packages mirror their target shape;
they are not a container for source projects.

## Integration boundaries

Nix modules describe how packages are installed, enabled, or disabled. They
should reference canonical sources under `packages/` when packaging source
projects. Development commands belong in the root `justfile` when they are
useful repository entrypoints, with package-local scripts retaining ownership
of build and test details.
