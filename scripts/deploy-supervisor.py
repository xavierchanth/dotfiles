#!/usr/bin/env python3
"""Run one command in an isolated process group and remove all local descendants."""

import errno
import os
import signal
import subprocess
import sys
import time

GRACE_SECONDS = 2.0
POLL_SECONDS = 0.02


def group_exists(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # Every process began beneath us, so this should not occur, but it still
        # means the group exists and must not be silently abandoned.
        return True
    return True


def signal_group(pgid: int, signum: int) -> None:
    try:
        os.killpg(pgid, signum)
    except ProcessLookupError:
        pass


def cleanup_group(pgid: int) -> None:
    signal_group(pgid, signal.SIGTERM)
    deadline = time.monotonic() + GRACE_SECONDS
    while group_exists(pgid) and time.monotonic() < deadline:
        time.sleep(POLL_SECONDS)
    if group_exists(pgid):
        signal_group(pgid, signal.SIGKILL)
        # Do not let inherited output descriptors outlive this wrapper.  KILL
        # cannot be ignored; wait for the kernel/reaper to remove the group.
        while group_exists(pgid):
            time.sleep(POLL_SECONDS)


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: deploy-supervisor COMMAND [ARG ...]", file=sys.stderr)
        return 64

    child = subprocess.Popen(argv, start_new_session=True)
    pgid = child.pid
    received_signal: int | None = None

    def forward(signum: int, _frame: object) -> None:
        nonlocal received_signal
        if received_signal is None:
            received_signal = signum
        signal_group(pgid, signum)

    previous = {}
    for signum in (signal.SIGINT, signal.SIGTERM):
        previous[signum] = signal.signal(signum, forward)
    try:
        status = child.wait()
    finally:
        cleanup_group(pgid)
        for signum, handler in previous.items():
            signal.signal(signum, handler)

    if received_signal is not None:
        return 128 + received_signal
    return status if status >= 0 else 128 - status


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except OSError as error:
        if error.errno == errno.ENOENT:
            print(f"deploy-supervisor: command not found: {sys.argv[1]}", file=sys.stderr)
            sys.exit(127)
        raise
