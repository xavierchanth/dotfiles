#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
target="$root/stow/agents/skills/guidelines/handoff/references/homelab.md"
case "${1:-}" in
  ""|--check) ;;
  *) echo "Usage: $0 [--check]" >&2; exit 2 ;;
esac
rendered=$(nix eval --offline --raw --file "$root/nix/handoff-reference.nix")
if [[ ${1:-} == --check ]]; then
  diff -u "$target" <(printf '%s\n' "$rendered")
else
  printf '%s\n' "$rendered" > "$target"
fi
