#!/usr/bin/env python3
"""Exercise authentication plumbing with fake commands and fake tokens only."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(os.environ.get("JIO_AUTH_HELPER", Path(__file__).resolve().parents[1] / "scripts/nix-with-github"))

class AuthHelper(unittest.TestCase):
    def invoke(self, existing="", token="ghp_fake_test", auth_exit=0, trace=False, result=0):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            gh = root / "gh"
            gh.write_text("#!/usr/bin/env python3\nimport os,sys\nprint(os.environ['FAKE_TOKEN'])\nsys.exit(int(os.environ['FAKE_AUTH_EXIT']))\n")
            nix = root / "nix"
            nix.write_text("#!/usr/bin/env python3\nimport json,os,sys\nfrom pathlib import Path\nif sys.argv[1:]==['config','show','access-tokens']:\n print(os.environ['FAKE_EXISTING'])\nelse:\n Path(os.environ['CAPTURE']).write_text(json.dumps({'args':sys.argv[1:],'config':os.environ['NIX_CONFIG']}))\n sys.exit(int(os.environ['FAKE_RESULT']))\n")
            gh.chmod(0o755)
            nix.chmod(0o755)
            env = dict(os.environ, PATH=str(root)+os.pathsep+os.environ['PATH'],
                       FAKE_TOKEN=token, FAKE_AUTH_EXIT=str(auth_exit), FAKE_EXISTING=existing,
                       FAKE_RESULT=str(result), CAPTURE=str(root/'capture.json'),
                       NIX_CONFIG="experimental-features = nix-command flakes")
            args = [os.environ.get("TEST_BASH", "/bin/bash")] + (["-x"] if trace else []) + [str(HELPER),"build","path with spaces","--no-link"]
            proc = subprocess.run(args,env=env,text=True,capture_output=True)
            saved = json.loads((root/'capture.json').read_text()) if (root/'capture.json').exists() else None
            if token:
                self.assertNotIn(token,proc.stdout+proc.stderr)
            self.assertEqual(set(x.name for x in root.iterdir()),{'gh','nix'} | ({'capture.json'} if saved else set()))
            return proc,saved

    def test_no_existing_tokens_and_exact_arguments(self):
        proc,saved=self.invoke()
        self.assertEqual(proc.returncode,0,proc.stderr)
        self.assertEqual(saved['args'],['build','path with spaces','--no-link'])
        self.assertIn('experimental-features = nix-command flakes',saved['config'])
        self.assertIn('access-tokens = github.com=ghp_fake_test',saved['config'])

    def test_replace_host_preserve_other_and_scoped_credentials(self):
        proc,saved=self.invoke(existing='example.com=fake_other github.com=old_fake github.com/org=fake_scoped')
        self.assertEqual(proc.returncode,0,proc.stderr)
        self.assertNotIn('github.com=old_fake',saved['config'])
        self.assertIn('example.com=fake_other',saved['config'])
        self.assertIn('github.com/org=fake_scoped',saved['config'])
        self.assertEqual(saved['config'].count('github.com=ghp_fake_test'),1)

    def test_failures_do_not_dispatch(self):
        for token,code in [('ghp_fake_test',1),('',0),('bad token',0),('bad\nsetting',0)]:
            with self.subTest(token=repr(token),code=code):
                proc,saved=self.invoke(token=token,auth_exit=code)
                self.assertNotEqual(proc.returncode,0)
                self.assertIsNone(saved)

    def test_trace_and_exit_status(self):
        proc,saved=self.invoke(trace=True,result=17)
        self.assertEqual(proc.returncode,17,proc.stderr)
        self.assertIsNotNone(saved)

if __name__ == '__main__':
    unittest.main()
