#!/usr/bin/env bash
set -euo pipefail

usage() { echo 'Usage: cage-session [--port PORT] [--name NAME] -- APP [ARG...]'; }
port=5900
name=
if [[ ${1:-} == --help ]]; then usage; exit 0; fi
while [[ ${1:-} == --port || ${1:-} == --name ]]; do
  [[ $# -ge 2 ]] || { usage >&2; exit 2; }
  case $1 in --port) port=$2 ;; --name) name=$2 ;; esac
  shift 2
done
[[ ${1:-} == -- ]] && shift
if [[ $# -eq 0 || ! $port =~ ^[0-9]{4,5}$ ]] || (( 10#$port < 1024 || 10#$port > 65535 )); then
  usage >&2
  exit 2
fi
port=$((10#$port))
name=${name:-$port}
[[ $name =~ ^[a-zA-Z0-9-]{1,64}$ ]] || { usage >&2; exit 2; }
[[ -n ${XDG_RUNTIME_DIR:-} && -d $XDG_RUNTIME_DIR && -O $XDG_RUNTIME_DIR ]] || {
  echo 'Run from a login session with an owned XDG_RUNTIME_DIR.' >&2
  exit 1
}
app=$(command -v -- "$1") || { echo "Application not found: $1" >&2; exit 127; }
shift
unset DISPLAY WAYLAND_DISPLAY
export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman
export XDG_SESSION_TYPE=wayland XKB_DEFAULT_LAYOUT=us
printf 'Session unit: cage-session-%s.scope\n' "$name"
exec systemd-run --user --scope --collect --quiet --unit="cage-session-$name" -- \
  dbus-run-session -- cage -- cage-session-app "$port" "$app" "$@"
