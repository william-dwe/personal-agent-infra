#!/usr/bin/env python3
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).parent
SYNC = ROOT / "laptop" / "envsync.sh"
STORE = ROOT / "envstore.py"

class EnvsyncTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        shim = self.root / "bin"
        shim.mkdir()
        (shim / "ssh").write_text("#!/bin/sh\nhost=$1; shift\ncase $1 in\n  .local/bin/env-put) cmd=put ;;\n  .local/bin/env-get) cmd=get ;;\n  .local/bin/env-diff) cmd=diff ;;\n  .local/bin/env-keys) cmd=keys ;;\nesac\nshift\nexec python3 \"$ENVSYNC_STORE\" \"$cmd\" \"$@\"\n")
        (shim / "ssh").chmod(0o755)
        self.env = os.environ | {"PATH": str(shim) + ":" + os.environ["PATH"], "ENVSTORE_DIR": str(self.root / "secrets"), "ENVSTORE_INFRA": str(self.root / "infra"), "ENVSYNC_STORE": str(STORE), "ENVSYNC_HOST": "test@host"}
        self.file = self.root / ".env"

    def tearDown(self): self.tmp.cleanup()

    def invoke(self, command, input=None):
        return subprocess.run(["bash", "-c", f'. "{SYNC}"; {command}'], input=input, text=True, capture_output=True, cwd=self.root, env=self.env)

    def test_push_pull_diff_and_check(self):
        self.file.write_text("A=one\n")
        push = self.invoke("envpush app .env")
        self.assertEqual(push.returncode, 0, push.stderr)
        self.assertEqual((self.root / "secrets" / "app.env").read_text(), "A=one\n")
        self.assertEqual(self.invoke("envdiff app .env").returncode, 0)
        self.file.write_text("A=two\n")
        self.assertEqual(self.invoke("envdiff app .env").returncode, 1)
        check = self.invoke("envcheck app .env")
        self.assertIn("⚠ app: local .env differs from VPS — run envpush or envpull", check.stdout)
        no = self.invoke("envpull app .env", "n\n")
        self.assertEqual(no.returncode, 1)
        self.assertEqual(self.file.read_text(), "A=two\n")
        yes = self.invoke("envpull app .env", "y\n")
        self.assertEqual(yes.returncode, 0, yes.stderr)
        self.assertEqual(self.file.read_text(), "A=one\n")
        self.assertEqual((self.root / ".env.bak").read_text(), "A=two\n")

if __name__ == "__main__":
    unittest.main()
