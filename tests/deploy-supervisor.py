#!/usr/bin/env python3
"""Hermetic process-group cleanup tests (Linux and Darwin)."""

import os
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
        return result, pid

    result, _ = invoke(23)
    assert result.returncode == 23, result
    result, _ = invoke(0)
    assert result.returncode == 0, result
    result, _ = invoke(19, "yes")
    assert result.returncode == 19 and not (root / "marker").exists(), result

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

print("deploy supervisor tests: ok")
