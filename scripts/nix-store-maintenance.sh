#!/usr/bin/env bash
set -euo pipefail

state_dir=${DOTFILES_NIX_MAINTENANCE_STATE_DIR:-/var/db/dotfiles-nix-maintenance}
test_mode=${DOTFILES_NIX_MAINTENANCE_TEST_MODE:-0}

if [[ $test_mode == 1 ]]; then
  pmset_command=${DOTFILES_NIX_MAINTENANCE_PMSET:-/usr/bin/pmset}
  ioreg_command=${DOTFILES_NIX_MAINTENANCE_IOREG:-/usr/sbin/ioreg}
  shlock_command=${DOTFILES_NIX_MAINTENANCE_SHLOCK:-/usr/bin/shlock}
  collect_command=${DOTFILES_NIX_MAINTENANCE_COLLECT_GARBAGE:-nix-collect-garbage}
  date_command=${DOTFILES_NIX_MAINTENANCE_DATE:-date}
else
  [[ $(id -u) == 0 ]] || { echo "nix-store-maintenance: must run as root" >&2; exit 1; }
  pmset_command=/usr/bin/pmset
  ioreg_command=/usr/sbin/ioreg
  shlock_command=/usr/bin/shlock
  collect_command=nix-collect-garbage
  date_command=/bin/date
fi

requested=$state_dir/requested
running=$state_dir/running
lock=$state_dir/run.lock

log() { printf 'nix-store-maintenance: %s\n' "$*"; }

prepare_state_dir() {
  [[ ! -L $state_dir ]] || { log "unsafe state directory: symbolic link" >&2; return 1; }
  [[ ! -e $state_dir || -d $state_dir ]] || { log "unsafe state directory: not a directory" >&2; return 1; }
  if [[ $test_mode == 1 ]]; then
    install -d -m 0700 "$state_dir"
  else
    install -d -o root -g wheel -m 0700 "$state_dir"
  fi

  local path
  for path in "$requested" "$running" "$lock"; do
    [[ ! -L $path ]] || { log "unsafe state entry: symbolic link: $path" >&2; return 1; }
    [[ ! -e $path || -f $path ]] || { log "unsafe state entry: not a regular file: $path" >&2; return 1; }
  done
}

request_cleanup() {
  prepare_state_dir
  local token
  token=$(mktemp "$state_dir/.requested.XXXXXX")
  printf '%s\n' "$($date_command -u +%Y-%m-%dT%H:%M:%SZ)" >"$token"
  chmod 0600 "$token"
  mv -fT "$token" "$requested"
  log "cleanup requested"
}

on_ac_power() {
  local power
  power=$("$pmset_command" -g batt) || return 1
  [[ ${power%%$'\n'*} == "Now drawing from 'AC Power'" ]]
}

idle_seconds() {
  local nanoseconds
  nanoseconds=$("$ioreg_command" -c IOHIDSystem | awk '/"HIDIdleTime"/ && !found { print $NF; found=1 } END { if (!found) exit 1 }') || return 1
  [[ $nanoseconds =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$((nanoseconds / 1000000000))"
}

restore_request() {
  if [[ -e $running ]]; then
    if [[ -e $requested ]]; then
      rm -f "$running"
    else
      mv -T "$running" "$requested"
    fi
  fi
}

run_cleanup() {
  prepare_state_dir
  [[ -e $requested || -e $running ]] || { log "no cleanup requested"; return 0; }

  if ! "$shlock_command" -f "$lock" -p "$$"; then
    log "cleanup already running"
    return 0
  fi
  local child_pid=
  cleanup_lock() { rm -f "$lock"; }
  interrupt_cleanup() {
    local signal_status=$1
    if [[ -n $child_pid ]]; then
      kill -TERM "$child_pid" 2>/dev/null || true
      wait "$child_pid" 2>/dev/null || true
    fi
    restore_request
    exit "$signal_status"
  }
  trap cleanup_lock EXIT
  trap 'interrupt_cleanup 130' INT
  trap 'interrupt_cleanup 143' TERM HUP

  # A terminated prior run leaves `running`; recover it before evaluating guards.
  restore_request
  [[ -e $requested ]] || { log "no cleanup requested"; return 0; }

  local hour
  hour=$($date_command +%H) || { log "skipped: could not determine local time"; return 0; }
  [[ $hour =~ ^[0-9]{2}$ ]] || { log "skipped: could not determine local time"; return 0; }
  hour=$((10#$hour))
  if (( hour < 4 || hour > 6 )); then
    log "skipped: outside the 04:00-06:59 local maintenance window"
    return 0
  fi

  if ! on_ac_power; then
    log "skipped: AC power is not connected"
    return 0
  fi

  local idle
  if ! idle=$(idle_seconds); then
    log "skipped: could not determine idle time"
    return 0
  fi
  if (( idle < 1800 )); then
    log "skipped: machine has been idle for ${idle}s (need 1800s)"
    return 0
  fi

  # Moving, rather than deleting, snapshots this request. A new request created
  # during collection lands at `requested` and is retained for a later run.
  mv -T "$requested" "$running"
  log "purging Nix profile generations older than three days, then removing store paths unreachable from retained generations and other GC roots"
  "$collect_command" --delete-older-than 3d &
  child_pid=$!
  if wait "$child_pid"; then
    child_pid=
    rm -f "$running"
    log "cleanup succeeded"
  else
    local status=$?
    child_pid=
    restore_request
    log "cleanup failed; request retained"
    return "$status"
  fi
}

case ${1:-} in
  request) request_cleanup ;;
  run) run_cleanup ;;
  *) echo "usage: nix-store-maintenance {request|run}" >&2; exit 64 ;;
esac
