#!/usr/bin/env python3
"""Exercise session argument boundaries, startup failures, and cleanup."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(os.environ.get("TEST_ROOT", Path(__file__).resolve().parents[1]))
BASH = os.environ.get("TEST_BASH", shutil.which("bash"))


class CageSessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, XDG_RUNTIME_DIR=str(self.root),
                        PATH=f"{self.bin}:{os.environ['PATH']}",
                        RECORD=str(self.root / "record"), WAYLAND_DISPLAY="wayland-test")

    def executable(self, name, code):
        path = self.bin / name
        path.write_text(code)
        path.chmod(0o755)

    def run_script(self, name, args):
        return subprocess.run([BASH, str(ROOT / "scripts" / name), *args],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_arguments_remain_literal(self):
        self.executable("systemd-run", "#!/usr/bin/env python3\nimport json,os,sys\n"
                        "json.dump({'argv':sys.argv[1:],'backend':os.environ.get('WLR_BACKENDS'),"
                        "'display':os.environ.get('WAYLAND_DISPLAY')},open(os.environ['RECORD'],'w'))\n")
        result = self.run_script("cage-session.sh", ["--port", "5901", "--", "printf", "a b", "$(touch nope)"])
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads((self.root / "record").read_text())
        self.assertEqual(record["argv"][-2:], ["a b", "$(touch nope)"])
        self.assertIn("--unit=cage-session-5901", record["argv"])
        self.assertEqual(record["backend"], "headless")
        self.assertIsNone(record["display"])

    def test_bad_port_and_missing_app(self):
        for args in [[], ["--port"], ["--port", "22", "--", "true"],
                     ["--port", "99999", "--", "true"], ["--port", "x", "--", "true"]]:
            self.assertEqual(self.run_script("cage-session.sh", args).returncode, 2)
        self.assertEqual(self.run_script("cage-session.sh", ["cage-no-such-app"]).returncode, 127)

    def test_vnc_failure_does_not_start_app(self):
        self.executable("wayvnc", "#!/usr/bin/env bash\nexit 1\n")
        result = self.run_script("cage-session-app.sh", ["5900", "touch", str(self.root / "started")])
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "started").exists())
        self.assertEqual(list(self.root.glob("cage-session.*")), [])

    def test_app_status_and_vnc_cleanup(self):
        self.executable("wayvnc", "#!/usr/bin/env python3\nimport os,signal,socket,sys,time\n"
                        "path=next(a.split('=',1)[1] for a in sys.argv if a.startswith('--socket='))\n"
                        "config=next(a.split('=',1)[1] for a in sys.argv if a.startswith('--config='))\n"
                        "assert 'address=127.0.0.1' in open(config).read()\n"
                        "open(os.environ['RECORD'],'w').write(str(os.getpid()))\n"
                        "s=socket.socket(socket.AF_UNIX);s.bind(path);s.listen()\n"
                        "time.sleep(30)\n")
        result = self.run_script("cage-session-app.sh", ["5900", BASH, "-c", "sleep 0.1; exit 42"])
        self.assertEqual(result.returncode, 42, result.stderr)
        pid = int((self.root / "record").read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)
        self.assertEqual(list(self.root.glob("cage-session.*")), [])


if __name__ == "__main__":
    unittest.main()
