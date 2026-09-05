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

deploy-host host:
  nix run .#deploy -- {{host}}

deploy-probe host:
  nix run .#deploy -- probe {{host}}

openwrt-render:
  nix build .#openwrt-charon-uci

openwrt-apply:
  nix run .#openwrt-apply-charon -- --apply
