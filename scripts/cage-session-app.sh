#!/usr/bin/env bash
set -euo pipefail

port=$1
shift
: "${XDG_RUNTIME_DIR:?}" "${WAYLAND_DISPLAY:?}"
session_dir=$(mktemp -d "$XDG_RUNTIME_DIR/cage-session.XXXXXX")
vnc_pid=
app_pid=
# shellcheck disable=SC2329
cleanup() {
  trap - EXIT
  [[ -z $app_pid ]] || kill "$app_pid" 2>/dev/null || true
  [[ -z $vnc_pid ]] || kill "$vnc_pid" 2>/dev/null || true
  for ((attempt=0; attempt<20; attempt++)); do
    if ! { [[ -n $app_pid ]] && kill -0 "$app_pid" 2>/dev/null; } &&
       ! { [[ -n $vnc_pid ]] && kill -0 "$vnc_pid" 2>/dev/null; }; then break; fi
    sleep 0.05
  done
  [[ -z $app_pid ]] || kill -KILL "$app_pid" 2>/dev/null || true
  [[ -z $vnc_pid ]] || kill -KILL "$vnc_pid" 2>/dev/null || true
  wait 2>/dev/null || true
  rm -rf -- "$session_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

printf 'address=127.0.0.1\nport=%s\nenable_auth=false\n' "$port" > "$session_dir/wayvnc.conf"
wayvnc --config="$session_dir/wayvnc.conf" --socket="$session_dir/control" &
vnc_pid=$!
for ((attempt=0; attempt<100; attempt++)); do
  kill -0 "$vnc_pid" 2>/dev/null || { echo 'WayVNC failed to start.' >&2; exit 1; }
  [[ ! -S $session_dir/control ]] || break
  sleep 0.05
done
[[ -S $session_dir/control ]] || { echo 'WayVNC startup timed out.' >&2; exit 1; }
printf 'Cage display: %s\nVNC: 127.0.0.1:%s\nControl socket: %s/control\n' "$WAYLAND_DISPLAY" "$port" "$session_dir"
"$@" &
app_pid=$!
status=0
finished=
wait -n -p finished "$app_pid" "$vnc_pid" || status=$?
if [[ $finished == "$vnc_pid" ]]; then
  echo 'WayVNC exited before the application.' >&2
  exit 1
fi
exit "$status"
