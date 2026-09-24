default:
  @just --list

build host="":
  ./scripts/build.sh {{host}}

clean:
  ./scripts/clean.sh

update *args:
  ./scripts/update.sh {{args}}

check:
  bash scripts/handoff-reference.sh --check
  nix flake check --all-systems --no-build --no-write-lock-file
  nix flake check --no-write-lock-file

handoff-reference:
  bash scripts/handoff-reference.sh

deploy *args:
  nix run .#deploy -- {{args}}

deploy-lab:
  nix run .#deploy -- lab

deploy-linux:
  nix run .#deploy -- linux

deploy-host host:
  nix run .#deploy -- {{host}}

deploy-probe host:
  nix run .#deploy -- probe {{host}}

openwrt-render:
  nix build .#openwrt-charon-uci

openwrt-apply:
  nix run .#openwrt-apply-charon -- --apply

# Requires the opt-in `vicinae-dev` group on the current host. That group
# disables the immutable extension package while the source watcher owns the bundle.
vicinae-extension-dev extension="window-management":
  #!/usr/bin/env bash
  set -euo pipefail
  extension={{quote(extension)}}
  if [[ ! "$extension" =~ ^[[:alnum:]][[:alnum:]_-]*$ ]]; then
    echo "invalid Vicinae extension name: $extension" >&2
    exit 2
  fi
  package_dir="{{justfile_directory()}}/packages/vicinae/$extension"
  if [[ ! -f "$package_dir/package.json" ]]; then
    echo "Vicinae extension package not found: $package_dir" >&2
    exit 2
  fi
  cd "$package_dir"
  npm install
  npm run dev
