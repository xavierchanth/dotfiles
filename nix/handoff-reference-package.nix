{ pkgs }:
let
  rendered = pkgs.writeText "homelab.md" (import ./handoff-reference.nix);
  snapshot = ../stow/agents/skills/guidelines/handoff/references/homelab.md;
in pkgs.runCommand "handoff-reference" { nativeBuildInputs = [ pkgs.diffutils ]; } ''
  if ! diff -u ${snapshot} ${rendered}; then
    echo 'Refresh the homelab reference with: bash scripts/handoff-reference.sh' >&2
    exit 1
  fi
  cp ${rendered} "$out"
''
