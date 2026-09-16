#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${TRACE_TESTS:-0} == 0 ]] || set -x
S=${DEPLOY_SCRIPT:?}; C=${CONSUMER_SCRIPT:-}; TEST_BASH=${TEST_BASH:-bash}; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"; LOG=$T/log; export LOG
REAL_STAT=$(command -v stat); REAL_MV=$(command -v mv); export REAL_STAT REAL_MV
mkdir "$T/bsd-bin"; export TEST_BSD_BIN=$T/bsd-bin
cat >"$T/bsd-bin/stat" <<'MOCK'
#!/usr/bin/env bash
[[ $1 == -f ]] || exit 1
case $2 in %u) format=%u;; %Lp) format=%a;; %z) format=%s;; *) exit 2;; esac
exec "$REAL_STAT" -c "$format" "$3"
MOCK
cat >"$T/bsd-bin/mv" <<'MOCK'
#!/usr/bin/env bash
for arg do [[ $arg != -*T* ]] || exit 2; done
exec "$REAL_MV" "$@"
MOCK
chmod +x "$T/bsd-bin/stat" "$T/bsd-bin/mv"
for c in nix nix-instantiate nix-store deploy-rs lab-update jj; do cat >"$T/bin/$c" <<'MOCK'
#!/usr/bin/env bash
command=$(basename "$0")
[[ -z ${DEPLOY_GITHUB_TOKEN+x} ]] || exit 88
echo "$command $*${DEPLOY_PROBE_SYSTEM:+ system=$DEPLOY_PROBE_SYSTEM}" >>"$LOG"
[[ -z ${NIX_SSHOPTS:-} ]] || echo "nix ssh options $NIX_SSHOPTS" >>"$LOG"
[[ $command != deploy-rs || -z ${DEPLOY_GITHUB_TOKEN+x} ]] || exit 89
[[ $command != deploy-rs || ${*: -1} != *"${FAIL_HOST:-__never__}"* ]] || exit 1
case $command in
  nix-instantiate) ln -sf /nix/store/probe.drv "${3:?}"; echo "$3";;
  nix-store) echo /nix/store/probe-output;;
esac
MOCK
chmod +x "$T/bin/$c"; done
cat >"$T/bin/gh" <<'MOCK'
#!/usr/bin/env bash
[[ -z ${DEPLOY_GITHUB_TOKEN+x} ]] || exit 88
echo "gh $*" >>"$LOG"
[[ ${GH_FAIL:-0} == 0 ]] || exit 1
printf '%s\n' 'ghp_123456789012345678901234567890123456'
MOCK
cat >"$T/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
[[ -z ${DEPLOY_GITHUB_TOKEN+x} ]] || exit 88
printf 'ssh argv' >>"$LOG"; printf ' %q' "$@" >>"$LOG"; echo >>"$LOG"
command=${*: -1}; remote_home=$TEST_REMOTE_HOME; mkdir -p "$remote_home/.local/state"
remote_path=$PATH
[[ ${MOCK_BSD_TOOLS:-0} == 0 ]] || remote_path=$TEST_BSD_BIN:$PATH
if [[ $command == 'bash -s -- chant' ]]; then
  cat >/dev/null
  echo 'ssh preflight' >>"$LOG"
  [[ ${SSH_PREFLIGHT_FAIL:-0} == 0 ]] || exit 95
elif [[ $command == bash\ -c* ]]; then
  PATH=$remote_path HOME=$remote_home XDG_STATE_HOME=$remote_home/.local/state USER=$(id -un) bash -c "$command"
  file=$remote_home/.local/state/dotfiles-deploy/github-api
  [[ -f $file && $(stat -c %a "$file") == 600 ]] || exit 91
  grep -qx 'ghp_123456789012345678901234567890123456' "$file" || exit 92
  echo 'ssh staged-stdin-ok' >>"$LOG"
  [[ ${SSH_STAGE_FAIL:-0} == 0 ]] || exit 93
else
  if [[ ${CLEANUP_FAIL_ONCE:-0} == 1 && ! -e $remote_home/cleanup-failed ]]; then touch "$remote_home/cleanup-failed"; exit 94; fi
  PATH=$remote_path HOME=$remote_home XDG_STATE_HOME=$remote_home/.local/state USER=$(id -un) bash -c "$command"
  echo 'ssh cleanup' >>"$LOG"
fi
MOCK
chmod +x "$T/bin/gh" "$T/bin/ssh"
cat >"$T/bin/uname" <<'MOCK'
#!/usr/bin/env bash
[[ ${1:-} == -n ]] || exit 2
echo "${MOCK_HOSTNAME:-client}"
MOCK
chmod +x "$T/bin/uname"
cat >"$T/inventory" <<'EOF'
poseidon	nixos	x86_64-linux	github-api	-	-	chant	-
zeus	nixos	x86_64-linux	github-api	-	-	chant	-
hades	nixos	x86_64-linux	-	-	-	chant	-
eris	darwin	aarch64-darwin	-	192.168.8.202	hades	chant	-
EOF
export TEST_REMOTE_HOME=$T/remote
export PATH="$T/bin:$PATH" DEPLOY_FLAKE=/source DEPLOY_INVENTORY="$T/inventory" DEPLOY_RS="$T/bin/deploy-rs" LAB_UPDATE="$T/bin/lab-update"
OUT=$T/stdout ERR=$T/stderr
run() { : >"$LOG"; : >"$OUT"; : >"$ERR"; "$TEST_BASH" "$S" "$@" >"$OUT" 2>"$ERR" || { status=$?; cat "$ERR" >&2; return "$status"; }; }
expect_failure() { if "$@"; then echo "expected failure: $*" >&2; return 1; fi; }
run --help; [[ ! -s $LOG ]]
expect_failure run unknown; [[ ! -s $LOG ]]
expect_failure run charon; [[ ! -s $LOG ]]
run hades; grep -Fq 'nix eval --json --no-write-lock-file /source#deploy.nodes.hades' "$LOG"; grep -Fq -- 'deploy-rs --skip-checks --remote-build /source#hades' "$LOG"; expect_failure grep -q interactive-sudo "$LOG"
grep -Fq 'chant@hades bash\ -s\ --\ chant' "$LOG"
for pair in '--dry-activate --dry-activate' '--test --test' '--boot --boot'; do read -r wrapper cli <<<"$pair"; run "$wrapper" hades; grep -Fq "deploy-rs $cli --skip-checks --remote-build /source#hades" "$LOG"; done
DEPLOY_GITHUB_TOKEN=ghp_123456789012345678901234567890123456 run hades; [[ $(grep -c '^deploy-rs ' "$LOG") == 1 && $(grep -c '^ssh preflight' "$LOG") == 1 ]]
DEPLOY_GITHUB_TOKEN=ghp_123456789012345678901234567890123456 run --boot poseidon; [[ $(grep -c '^deploy-rs ' "$LOG") == 1 && $(grep -c '^ssh preflight' "$LOG") == 1 && $(grep -c '^gh ' "$LOG") == 0 ]]
SSH_PREFLIGHT_FAIL=1; export SSH_PREFLIGHT_FAIL; expect_failure run poseidon
grep -q 'activation preflight failed' "$ERR"
if grep -Eq '^(deploy-rs |ssh staged-stdin-ok|ssh cleanup)' "$LOG"; then exit 1; fi
unset SSH_PREFLIGHT_FAIL
GH_FAIL=1 DEPLOY_GITHUB_TOKEN=bad run --dry-activate poseidon; [[ $(grep -c '^gh auth token' "$LOG") == 1 && $(grep -c '^ssh ' "$LOG") == 0 ]]; grep -q 'warning:' "$ERR"
run --dry-activate poseidon; [[ $(grep -c '^ssh ' "$LOG") == 0 ]]
run --dry-activate eris; grep -Fq 'deploy-rs --dry-activate --skip-checks --remote-build /source#eris' "$LOG"
run poseidon; [[ $(grep -c '^gh auth token' "$LOG") == 1 && $(grep -c '^ssh staged-stdin-ok' "$LOG") == 1 && $(grep -c '^ssh cleanup' "$LOG") == 1 ]]
[[ ! -e $TEST_REMOTE_HOME/.local/state/dotfiles-deploy/github-api ]]
if grep -q 'ghp_' "$LOG" "$OUT" "$ERR"; then exit 1; fi
DEPLOY_GITHUB_TOKEN=ghp_123456789012345678901234567890123456; export DEPLOY_GITHUB_TOKEN; run poseidon; unset DEPLOY_GITHUB_TOKEN
DEPLOY_GITHUB_TOKEN=ghp_123456789012345678901234567890123456; export DEPLOY_GITHUB_TOKEN; GH_FAIL=1; export GH_FAIL; run --dry-activate poseidon; [[ $(grep -c '^gh ' "$LOG") == 0 && ! -s $ERR ]]; unset GH_FAIL DEPLOY_GITHUB_TOKEN
CLEANUP_FAIL_ONCE=1; export CLEANUP_FAIL_ONCE; rm -f "$TEST_REMOTE_HOME/cleanup-failed"; run poseidon; [[ ! -e $TEST_REMOTE_HOME/.local/state/dotfiles-deploy/github-api && $(grep -c '^ssh argv' "$LOG") == 4 ]]; unset CLEANUP_FAIL_ONCE
GH_FAIL=1; export GH_FAIL; expect_failure run zeus; [[ $(grep -c '^gh ' "$LOG") == 1 ]]; if grep -Eq '^(nix|deploy-rs|ssh) ' "$LOG"; then exit 1; fi; unset GH_FAIL
run --dry-activate lab; [[ $(grep -c '^deploy-rs ' "$LOG") == 4 ]]
for mode in '' --dry-activate --test --boot; do
  if [[ -n $mode ]]; then run "$mode" linux; else run linux; fi
  [[ $(grep '^deploy-rs ' "$LOG" | sed 's/.*#//' | paste -sd, -) == poseidon,zeus,hades ]]
  if grep -q eris "$LOG"; then exit 1; fi
done
expect_failure run linux extra; [[ ! -s $LOG ]]
FAIL_HOST='#zeus'; export FAIL_HOST; expect_failure run linux
[[ $(grep '^deploy-rs ' "$LOG" | sed 's/.*#//' | paste -sd, -) == poseidon,zeus ]]
unset FAIL_HOST
MOCK_HOSTNAME=hades; export MOCK_HOSTNAME; expect_failure run linux; [[ ! -s $LOG ]]; unset MOCK_HOSTNAME
MOCK_HOSTNAME=eris; export MOCK_HOSTNAME; run --dry-activate linux; [[ $(grep -c '^deploy-rs ' "$LOG") == 3 ]]; unset MOCK_HOSTNAME
for unsafe in test boot; do
  expect_failure run "--$unsafe" eris; [[ ! -s $LOG ]]
  expect_failure run "--$unsafe" lab; [[ ! -s $LOG ]]
done
export FAIL_HOST='#zeus'; expect_failure run lab; [[ $(grep -c '^deploy-rs ' "$LOG") == 2 && $(grep -c '^gh auth token' "$LOG") == 1 ]]; [[ ! -e $TEST_REMOTE_HOME/.local/state/dotfiles-deploy/github-api ]]; unset FAIL_HOST
SSH_STAGE_FAIL=1; export SSH_STAGE_FAIL; expect_failure run poseidon; [[ ! -e $TEST_REMOTE_HOME/.local/state/dotfiles-deploy/github-api ]]; unset SSH_STAGE_FAIL
MOCK_HOSTNAME=hades; export MOCK_HOSTNAME; expect_failure run hades; [[ ! -s $LOG ]]; expect_failure run lab; [[ ! -s $LOG ]]; unset MOCK_HOSTNAME
run --assure hades; grep -Fq 'jj root' "$LOG"; grep -Fq 'lab-update --dry-run hades' "$LOG"; grep -Fq 'lab-update hades' "$LOG"
expect_failure run --assure eris
expect_failure run probe charon
printf 'probe hades\n' >"$T/tty"; export DEPLOY_TTY_PATH="$T/tty"
run probe hades
grep -Fq 'nix-instantiate --impure --add-root ' "$LOG"
grep -Fq 'system=x86_64-linux' "$LOG"
grep -Fq 'nix copy --to ssh-ng://chant@hades /nix/store/probe.drv' "$LOG"
grep -Fq 'nix-store --store ssh-ng://chant@hades --no-gc-warning --realise /nix/store/probe.drv' "$LOG"
unset DEPLOY_TTY_PATH
# Production composition requires credentials on all four hosts. Keep the
# earlier fixture to exercise generic no-credential and assured-path support.
sed 's/hades\tnixos\tx86_64-linux\t-/hades\tnixos\tx86_64-linux\tgithub-api/; s/eris\tdarwin\taarch64-darwin\t-/eris\tdarwin\taarch64-darwin\tgithub-api/' "$T/inventory" >"$T/production-inventory"
export DEPLOY_INVENTORY=$T/production-inventory
expect_failure run --assure hades; grep -q 'does not support credential-requiring hosts' "$ERR"; [[ ! -s $LOG ]]
run hades; [[ $(grep -c '^ssh staged-stdin-ok' "$LOG") == 1 ]]
MOCK_BSD_TOOLS=1; export MOCK_BSD_TOOLS
run eris
[[ $(grep -c '^ssh staged-stdin-ok' "$LOG") == 1 && $(grep -c '^ssh cleanup' "$LOG") == 1 && $(grep -c '^ssh preflight' "$LOG") == 0 ]]
[[ $(grep -c 'ProxyJump=hades chant@192.168.8.202' "$LOG") == 2 ]]
if grep -q 'ghp_' "$LOG" "$OUT" "$ERR"; then exit 1; fi
[[ ! -e $TEST_REMOTE_HOME/.local/state/dotfiles-deploy/github-api ]]
# Failed Darwin staging still cleans up through the same inventory route.
SSH_STAGE_FAIL=1; export SSH_STAGE_FAIL; expect_failure run eris; unset SSH_STAGE_FAIL
[[ ! -e $TEST_REMOTE_HOME/.local/state/dotfiles-deploy/github-api ]]
[[ $(grep -c 'ProxyJump=hades chant@192.168.8.202' "$LOG") == 2 ]]
# Portable mv must never treat an unexpected credential directory as a target.
credential_dir=$TEST_REMOTE_HOME/.local/state/dotfiles-deploy/github-api
mkdir "$credential_dir"
expect_failure run eris
[[ -d $credential_dir && -z $(ls -A "$credential_dir") ]]
rmdir "$credential_dir"
unset MOCK_BSD_TOOLS
run lab; [[ $(grep -c '^ssh staged-stdin-ok' "$LOG") == 4 && $(grep -c '^deploy-rs ' "$LOG") == 4 ]]
sed 's/hades\tnixos\tx86_64-linux\tgithub-api\t-\t-\tchant\t-/hades\tnixos\tx86_64-linux\tgithub-api\t-\t-\tdeploy\t.ssh\/id_ed25519_dotfiles_deploy/' "$T/production-inventory" >"$T/dedicated-inventory"
export DEPLOY_INVENTORY=$T/dedicated-inventory
run hades
grep -Fq 'deploy@hades bash\ -s\ --\ chant' "$LOG"
grep -Fq 'chant@hades bash\ -c' "$LOG"
grep -Fq -- '-o IdentitiesOnly=yes -i ' "$LOG"
if grep -Fq 'deploy@hades bash\ -c' "$LOG"; then exit 1; fi
printf 'probe hades\n' >"$T/tty"; export DEPLOY_TTY_PATH="$T/tty"
run probe hades
grep -Fq 'nix copy --to ssh-ng://deploy@hades /nix/store/probe.drv' "$LOG"
grep -Fq 'IdentitiesOnly=yes' "$LOG"
unset DEPLOY_TTY_PATH
export DEPLOY_INVENTORY=$T/production-inventory
printf 'probe eris\n' >"$T/tty"; export DEPLOY_TTY_PATH="$T/tty"
run probe eris
grep -Fq 'nix copy --to ssh-ng://chant@192.168.8.202 /nix/store/probe.drv' "$LOG"
grep -Fq 'ProxyJump=hades' "$LOG"
unset DEPLOY_TTY_PATH
if [[ -n $C ]]; then
  consumer_home=$T/home; mkdir -p "$consumer_home/.local/state/dotfiles-deploy"; chmod 700 "$consumer_home/.local/state/dotfiles-deploy"
  credential=$consumer_home/.local/state/dotfiles-deploy/github-api
  printf '%s\n' 'ghp_123456789012345678901234567890123456' >"$credential"; chmod 600 "$credential"
  [[ $(env -u USER HOME="$consumer_home" "$TEST_BASH" "$C" github-api) == ghp_* && ! -e $credential ]]
  { printf g; head -c 511 /dev/zero | tr '\0' a; printf '\n'; } >"$credential"; chmod 600 "$credential"; [[ $(env -u USER HOME="$consumer_home" "$TEST_BASH" "$C" github-api | wc -c) == 513 && ! -e $credential ]]
  printf x >"$credential"; chmod 644 "$credential"; expect_failure env HOME="$consumer_home" USER="$(id -un)" "$TEST_BASH" "$C" github-api; [[ ! -e $credential ]]
  printf short >"$credential"; chmod 600 "$credential"; expect_failure env HOME="$consumer_home" USER="$(id -un)" "$TEST_BASH" "$C" github-api; [[ ! -e $credential ]]
  head -c 514 /dev/zero | tr '\0' a >"$credential"; chmod 600 "$credential"; expect_failure env HOME="$consumer_home" USER="$(id -un)" "$TEST_BASH" "$C" github-api; [[ ! -e $credential ]]
  printf '%s\n' 'ghp_123456789012345678901234567890123456' >"$credential"; chmod 600 "$credential"; touch -d '13 hours ago' "$credential"; expect_failure env HOME="$consumer_home" USER="$(id -un)" "$TEST_BASH" "$C" github-api; [[ ! -e $credential ]]
  ln -s "$T/elsewhere" "$credential"; expect_failure env HOME="$consumer_home" USER="$(id -un)" "$TEST_BASH" "$C" github-api; [[ ! -L $credential ]]
  chmod 755 "$consumer_home/.local/state/dotfiles-deploy"; printf '%s\n' 'ghp_123456789012345678901234567890123456' >"$credential"; chmod 600 "$credential"; expect_failure env HOME="$consumer_home" USER="$(id -un)" "$TEST_BASH" "$C" github-api; [[ ! -e $credential ]]; chmod 700 "$consumer_home/.local/state/dotfiles-deploy"
fi
echo 'deploy hermetic tests: ok'
