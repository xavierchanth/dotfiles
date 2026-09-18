#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script=${NIX_STORE_MAINTENANCE_SCRIPT:-$root/scripts/nix-store-maintenance.sh}
clean_script=${DOTFILES_CLEAN_SCRIPT:-$root/scripts/clean.sh}
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/state"
log=$test_root/calls

cat >"$test_root/bin/pmset" <<'EOF'
#!/usr/bin/env bash
printf "Now drawing from '%s Power'\n" "${POWER_SOURCE:-AC}"
EOF
cat >"$test_root/bin/ioreg" <<'EOF'
#!/usr/bin/env bash
printf '    | |   "HIDIdleTime" = %s\n' "${IDLE_NS:-1800000000000}"
EOF
cat >"$test_root/bin/shlock" <<'EOF'
#!/usr/bin/env bash
while (( $# )); do case $1 in -f) lock=$2; shift 2;; -p) pid=$2; shift 2;; esac; done
if [[ -f $lock ]]; then
  read -r owner <"$lock"
  kill -0 "$owner" 2>/dev/null || rm -f "$lock"
fi
( set -o noclobber; printf '%s\n' "$pid" >"$lock" ) 2>/dev/null
EOF
cat >"$test_root/bin/nix-collect-garbage" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALL_LOG"
[[ ${COLLECT_FAIL:-0} != 1 ]] || exit 23
[[ ${REQUEST_DURING_RUN:-0} != 1 ]] || touch "$STATE_DIR/requested"
if [[ ${COLLECT_SLEEP:-0} == 1 ]]; then
  printf '%s\n' "$$" >"$CHILD_PID_FILE"
  trap 'exit 143' TERM
  sleep 30 & wait $!
fi
EOF
cat >"$test_root/bin/date" <<'EOF'
#!/usr/bin/env bash
if [[ $* == *+%H* ]]; then printf '%s\n' "${HOUR:-04}"; else printf '%s\n' 2026-09-18T04:00:00Z; fi
EOF
chmod +x "$test_root/bin/"*

export DOTFILES_NIX_MAINTENANCE_TEST_MODE=1
export DOTFILES_NIX_MAINTENANCE_STATE_DIR=$test_root/state
export DOTFILES_NIX_MAINTENANCE_PMSET=$test_root/bin/pmset
export DOTFILES_NIX_MAINTENANCE_IOREG=$test_root/bin/ioreg
export DOTFILES_NIX_MAINTENANCE_SHLOCK=$test_root/bin/shlock
export DOTFILES_NIX_MAINTENANCE_COLLECT_GARBAGE=$test_root/bin/nix-collect-garbage
export DOTFILES_NIX_MAINTENANCE_DATE=$test_root/bin/date
export CALL_LOG=$log STATE_DIR=$test_root/state

run() { bash "$script" "$@"; }
reset() { rm -f "$test_root/state/"* "$log"; run request >/dev/null; }

run request >/dev/null
[[ -f $test_root/state/requested ]]

rm -f "$test_root/state/requested"
POWER_SOURCE=Battery IDLE_NS=0 HOUR=12 run run >/dev/null
[[ ! -e $log ]]
run request >/dev/null

HOUR=12 run run >/dev/null
[[ -f $test_root/state/requested && ! -e $log ]]

POWER_SOURCE=Battery run run >/dev/null
[[ -f $test_root/state/requested && ! -e $log ]]

IDLE_NS=1799000000000 run run >/dev/null
[[ -f $test_root/state/requested && ! -e $log ]]

reset
run run >/dev/null
[[ ! -e $test_root/state/requested && ! -e $test_root/state/running ]]
[[ $(cat "$log") == "--delete-older-than 3d" ]]

reset
if COLLECT_FAIL=1 run run >/dev/null 2>&1; then exit 1; fi
[[ -f $test_root/state/requested && ! -e $test_root/state/running ]]

reset
REQUEST_DURING_RUN=1 run run >/dev/null
[[ -f $test_root/state/requested && ! -e $test_root/state/running ]]

reset
printf '%s\n' "$$" >"$test_root/state/run.lock"
run run >/dev/null
[[ -f $test_root/state/requested && ! -e $log ]]

reset
printf '99999999\n' >"$test_root/state/run.lock"
run run >/dev/null
[[ ! -e $test_root/state/requested && ! -e $test_root/state/run.lock ]]
[[ $(cat "$log") == "--delete-older-than 3d" ]]

reset
mv "$test_root/state/requested" "$test_root/state/running"
run run >/dev/null
[[ ! -e $test_root/state/running ]]
[[ $(cat "$log") == "--delete-older-than 3d" ]]

grep -Fq 'retention_days=7' "$clean_script"
grep -Fq "nix-collect-garbage --delete-older-than \"\${retention_days}d\"" "$clean_script"
grep -Fq "brew cleanup --prune=\"\$retention_days\"" "$clean_script"

reset
export COLLECT_SLEEP=1 CHILD_PID_FILE=$test_root/child.pid
bash "$script" run >/dev/null 2>&1 & runner=$!
for _ in {1..50}; do [[ -f $CHILD_PID_FILE ]] && break; sleep 0.02; done
[[ -f $CHILD_PID_FILE ]]
child=$(cat "$CHILD_PID_FILE")
kill -TERM "$runner"
if wait "$runner"; then exit 1; fi
if kill -0 "$child" 2>/dev/null; then exit 1; fi
[[ -f $test_root/state/requested && ! -e $test_root/state/running && ! -e $test_root/state/run.lock ]]
unset COLLECT_SLEEP CHILD_PID_FILE

mv "$test_root/state" "$test_root/state.real"
ln -s "$test_root/state.real" "$test_root/state"
if run request >/dev/null 2>&1; then exit 1; fi

rm "$test_root/state"
mv "$test_root/state.real" "$test_root/state"
rm -f "$test_root/state/"*
mkdir "$test_root/redirect"
for entry in requested running run.lock; do
  ln -s "$test_root/redirect" "$test_root/state/$entry"
  if run request >/dev/null 2>&1; then exit 1; fi
  rm "$test_root/state/$entry"
done
[[ -z $(find "$test_root/redirect" -mindepth 1 -print -quit) ]]
mkdir "$test_root/state/requested"
if run request >/dev/null 2>&1; then exit 1; fi

echo 'nix store maintenance tests: ok'
