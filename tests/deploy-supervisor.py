#!/usr/bin/env python3
"""Hermetic process-group cleanup tests (Linux and Darwin)."""

import os
import pty
import select
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

supervisor = sys.argv[1]
python = sys.executable


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    fake = root / "fake.py"
    fake.write_text("""import subprocess, sys, pathlib
root, status, ignore = sys.argv[1], int(sys.argv[2]), sys.argv[3]
code = '''import os, signal, sys, time, pathlib
root, ignore = sys.argv[1], sys.argv[2]
if ignore == "yes": signal.signal(signal.SIGTERM, signal.SIG_IGN)
pathlib.Path(root, "pid").write_text(str(os.getpid()))
time.sleep(3 if ignore == "yes" else .5)
pathlib.Path(root, "marker").write_text("orphan ran")
print("delayed stdout marker", flush=True)
print("delayed stderr marker", file=sys.stderr, flush=True)
time.sleep(30)
'''
subprocess.Popen([sys.executable, '-c', code, root, ignore])
for _ in range(200):
    if pathlib.Path(root, "pid").exists(): break
    import time; time.sleep(.005)
sys.exit(status)
""")

    def invoke(status: int, ignore: str = "no") -> tuple[subprocess.CompletedProcess[str], int]:
        for name in ("pid", "marker"):
            try: (root / name).unlink()
            except FileNotFoundError: pass
        result = subprocess.run([supervisor, python, str(fake), str(root), str(status), ignore],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=8)
        pid = int((root / "pid").read_text())
        assert not alive(pid), f"descendant {pid} survived wrapper return"
        time.sleep(.7)
        assert not (root / "marker").exists(), "delayed descendant marker appeared"
        assert "delayed" not in result.stdout + result.stderr, "descendant output escaped cleanup"
        return result, pid

    result, _ = invoke(23)
    assert result.returncode == 23, result
    result, _ = invoke(0)
    assert result.returncode == 0, result
    result, _ = invoke(19, "yes")
    assert result.returncode == 19 and not (root / "marker").exists(), result

    # Deterministically signal after Popen created the child but before the
    # supervisor publishes its PGID.  The preinstalled handler must queue it.
    for name in ("pid", "marker"):
        try: (root / name).unlink()
        except FileNotFoundError: pass
    environment = dict(os.environ, DEPLOY_SUPERVISOR_TEST_SPAWN_PAUSE="1")
    paused = subprocess.Popen([supervisor, python, str(fake), str(root), "0", "no"],
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                              env=environment)
    assert paused.stderr is not None
    assert paused.stderr.readline().strip().endswith("spawn-paused")
    os.kill(paused.pid, signal.SIGTERM)
    paused.communicate(timeout=8)
    assert paused.returncode == 143
    assert not alive(int((root / "pid").read_text()))

    unrelated = subprocess.Popen([python, "-c", "import time; time.sleep(30)"])
    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            for name in ("pid", "marker"):
                try: (root / name).unlink()
                except FileNotFoundError: pass
            wrapped = subprocess.Popen([supervisor, python, str(fake), str(root), "0", "no"],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            deadline = time.monotonic() + 3
            while not (root / "pid").exists() and time.monotonic() < deadline:
                time.sleep(.02)
            assert (root / "pid").exists(), "fake descendant did not start"
            pid = int((root / "pid").read_text())
            os.kill(wrapped.pid, signum)
            wrapped.communicate(timeout=8)
            assert wrapped.returncode == 128 + signum, wrapped.returncode
            assert not alive(pid), f"descendant survived signal {signum}"
            assert unrelated.poll() is None, "unrelated process was killed"
    finally:
        unrelated.terminate()
        unrelated.wait()

# A real controlling PTY proves that changing groups does not lose /dev/tty or
# interactive reads, and that terminal-generated Ctrl-C reaches the foreground
# child group while the supervisor regains terminal ownership for cleanup.
def pty_run(command: list[str], writes: list[bytes], ctrl_c: bool = False) -> tuple[int, bytes]:
    pid, master = pty.fork()
    if pid == 0:
        os.execv(supervisor, [supervisor, *command])
    output = bytearray()
    try:
        for data in writes:
            os.write(master, data)
            time.sleep(.1)
        if ctrl_c:
            ready_deadline = time.monotonic() + 3
            while b"READY" not in output and time.monotonic() < ready_deadline:
                ready, _, _ = select.select([master], [], [], .1)
                if ready:
                    output.extend(os.read(master, 4096))
            assert b"READY" in output, output
            os.write(master, b"\x03")
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], .1)
            if ready:
                try: output.extend(os.read(master, 4096))
                except OSError: break
            waited, raw = os.waitpid(pid, os.WNOHANG)
            if waited:
                return os.waitstatus_to_exitcode(raw), bytes(output)
        raise AssertionError("PTY supervisor timed out")
    finally:
        os.close(master)

interactive = """import sys
first = input()
with open('/dev/tty', 'r') as tty: second = tty.readline().strip()
print('PTY-OK:' + first + ':' + second, flush=True)
"""
status, output = pty_run([python, "-c", interactive], [b"first\n", b"second\n"])
assert status == 0 and b"PTY-OK:first:second" in output, (status, output)
status, _ = pty_run([python, "-c", "import time; print('READY', flush=True); time.sleep(30)"], [], ctrl_c=True)
assert status == 130, status

print("deploy supervisor tests: ok")
