#!/usr/bin/env bash
set -Eeuo pipefail
S=${DEPLOY_PREFLIGHT:?}; TEST_BASH=${TEST_BASH:-bash}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
cat >"$T/bin/ps" <<'MOCK'
#!/usr/bin/env bash
[[ ${PS_FAIL:-0} == 0 ]] || exit 1
printf '%s\n' "${PROCESS_ROWS:-}"
MOCK
cat >"$T/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
[[ ${SYSTEMCTL_FAIL:-0} == 0 ]] || exit 1
printf '%s\n' 'LoadState=loaded' "ActiveState=${ACTIVE_STATE:-active}" 'SubState=exited' "MainPID=${MAIN_PID:-0}" "ControlPID=${CONTROL_PID:-0}"
MOCK
chmod +x "$T/bin/ps" "$T/bin/systemctl"
export PATH="$T/bin:$PATH"
run() { "$TEST_BASH" "$S" chant >"$T/out" 2>"$T/err"; }
blocked() { if run; then echo 'expected busy preflight to fail' >&2; exit 1; fi; grep -q 'refusing overlapping deployment' "$T/err"; }
run
if "$TEST_BASH" "$S" >"$T/out" 2>"$T/err"; then exit 1; fi
grep -q 'invalid Home Manager recipient' "$T/err"
# Background infrastructure and unprivileged commands do not imply activation.
PROCESS_ROWS=$'0 700 1 Ssl 10:00 nix-daemon --daemon\n1000 701 1 S 00:10 editor /tmp/activate\n0 702 1 Ss 10:00 /nix/store/abc-systemd/bin/systemd'; export PROCESS_ROWS; run
for command in \
  '/nix/store/m5bf-activatable-system/activate-rs wait /nix/store/m5bf-activatable-system --activation-timeout 3900' \
  '/nix/store/yb0c-deploy-rs-0.1.0/bin/activate wait /nix/store/m5bf-activatable-system' \
  '/nix/store/yb0c-deploy-rs-0.1.0/bin/activate activate /nix/store/m5bf-activatable-system' \
  '/nix/store/yb0c-deploy-rs-0.1.0/bin/activate revoke --profile-path /nix/var/nix/profiles/system' \
  'bash /nix/store/abc-nixos-system/bin/switch-to-configuration switch' \
  'bash /nix/store/abc-activatable-system/deploy-rs-activate' \
  '/run/current-system/sw/bin/nixos-rebuild switch'; do
  PROCESS_ROWS="0 18929 1 Sl 03:51 $command"; blocked; grep -q '18929' "$T/err"
done
unset PROCESS_ROWS
ACTIVE_STATE=activating blocked
ACTIVE_STATE=deactivating blocked
MAIN_PID=19742 blocked
CONTROL_PID=19743 blocked
ACTIVE_STATE=failed run
for signal in PS_FAIL SYSTEMCTL_FAIL; do
  if env "$signal=1" "$TEST_BASH" "$S" chant >"$T/out" 2>"$T/err"; then exit 1; fi
  grep -q 'cannot inspect' "$T/err"
done
echo 'deploy preflight tests: ok'
