#!/usr/bin/env python3
"""Run one command in an isolated process group and remove local descendants."""

import os
import signal
import subprocess
import sys
import time

GRACE_SECONDS = 2.0
KILL_SECONDS = 2.0
POLL_SECONDS = 0.02
ERROR_STATUS = 125


class SupervisorError(Exception):
    """A controlled supervision failure."""


def group_exists(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except (ProcessLookupError, PermissionError):
        # Darwin may report EPERM for an empty group whose former leader has
        # exited.  Every member was created with our uid, so EPERM cannot denote
        # a surviving inaccessible member here.
        return False
    return True


def signal_group(pgid: int, signum: int) -> None:
    try:
        os.killpg(pgid, signum)
    except (ProcessLookupError, PermissionError):
        pass


def wait_group_gone(pgid: int, seconds: float) -> bool:
    deadline = time.monotonic() + seconds
    while group_exists(pgid) and time.monotonic() < deadline:
        time.sleep(POLL_SECONDS)
    return not group_exists(pgid)


def cleanup_group(pgid: int) -> None:
    signal_group(pgid, signal.SIGTERM)
    if wait_group_gone(pgid, GRACE_SECONDS):
        return
    signal_group(pgid, signal.SIGKILL)
    if not wait_group_gone(pgid, KILL_SECONDS):
        raise SupervisorError(
            f"local process group {pgid} remained after SIGKILL; remote state is unknown"
        )


def set_foreground(fd: int, pgid: int) -> None:
    previous = signal.signal(signal.SIGTTOU, signal.SIG_IGN)
    try:
        os.tcsetpgrp(fd, pgid)
    finally:
        signal.signal(signal.SIGTTOU, previous)


def child_gate(argv: list[str]) -> int:
    """Wait without touching the terminal, then replace this group leader."""
    try:
        gate_fd = int(argv[0])
        released = os.read(gate_fd, 1)
        os.close(gate_fd)
        if released != b"G":
            print("deploy-supervisor: child gate closed before release", file=sys.stderr)
            return ERROR_STATUS
        os.execvp(argv[1], argv[1:])
    except FileNotFoundError:
        print(f"deploy-supervisor: command not found: {argv[1]}", file=sys.stderr)
        return 127
    except (OSError, ValueError, IndexError) as error:
        print(f"deploy-supervisor: child gate failed: {error}", file=sys.stderr)
        return ERROR_STATUS
    return ERROR_STATUS


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: deploy-supervisor COMMAND [ARG ...]", file=sys.stderr)
        return 64

    state: dict[str, object] = {"pgid": None, "pending": [], "received": None}

    def forward(signum: int, _frame: object) -> None:
        if state["received"] is None:
            state["received"] = signum
        pgid = state["pgid"]
        if pgid is None:
            pending = state["pending"]
            assert isinstance(pending, list)
            pending.append(signum)
        else:
            signal_group(int(pgid), signum)

    previous_handlers = {
        signum: signal.signal(signum, forward)
        for signum in (signal.SIGINT, signal.SIGTERM)
    }
    child = None
    pgid = None
    original_foreground = None
    gate_read = None
    gate_write = None
    tty_fd = sys.stdin.fileno()
    status = ERROR_STATUS
    cleanup_error = None
    gate_failed = False
    try:
        # The new group leader initially runs only our pipe gate.  It cannot
        # touch the controlling TTY before the parent makes its group foreground.
        gate_read, gate_write = os.pipe()
        os.set_inheritable(gate_read, True)
        child = subprocess.Popen(
            [sys.executable, os.path.abspath(__file__), "--_child-gate", str(gate_read), *argv],
            process_group=0,
            pass_fds=(gate_read,),
        )
        os.close(gate_read)
        gate_read = None
        if os.environ.get("DEPLOY_SUPERVISOR_TEST_SPAWN_PAUSE"):
            print("deploy-supervisor: spawn-paused", file=sys.stderr, flush=True)
            time.sleep(0.5)
        pgid = child.pid
        state["pgid"] = pgid
        pending = state["pending"]
        assert isinstance(pending, list)
        for signum in pending:
            signal_group(pgid, int(signum))

        if os.isatty(tty_fd):
            original_foreground = os.tcgetpgrp(tty_fd)
            set_foreground(tty_fd, pgid)
        try:
            os.write(gate_write, b"G")
        except BrokenPipeError:
            if state["received"] is None:
                print("deploy-supervisor: child exited before gate release", file=sys.stderr)
                gate_failed = True
        finally:
            os.close(gate_write)
            gate_write = None
        child_status = child.wait()
        if not gate_failed or state["received"] is not None:
            status = child_status if child_status >= 0 else 128 - child_status
    except FileNotFoundError:
        print(f"deploy-supervisor: command not found: {argv[0]}", file=sys.stderr)
        status = 127
    except (OSError, subprocess.SubprocessError) as error:
        print(f"deploy-supervisor: supervision failed: {error}", file=sys.stderr)
        status = ERROR_STATUS
    finally:
        for fd in (gate_read, gate_write):
            if fd is not None:
                try:
                    os.close(fd)
                except OSError:
                    pass
        if pgid is not None:
            try:
                cleanup_group(pgid)
            except (OSError, SupervisorError) as error:
                cleanup_error = error
        if original_foreground is not None:
            try:
                set_foreground(tty_fd, original_foreground)
            except OSError as error:
                cleanup_error = cleanup_error or error
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)

    if cleanup_error is not None:
        print(f"deploy-supervisor: cleanup failed: {cleanup_error}", file=sys.stderr)
        return ERROR_STATUS
    if state["received"] is not None:
        return 128 + int(state["received"])
    return status


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if arguments[:1] == ["--_child-gate"]:
        sys.exit(child_gate(arguments[1:]))
    sys.exit(main(arguments))
