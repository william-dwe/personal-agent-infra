#!/usr/bin/env python3
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name("envstore.py")


class EnvstoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.store = self.root / "secrets"
        self.infra = self.root / "infra.env"
        self.env = os.environ | {"ENVSTORE_DIR": str(self.store), "ENVSTORE_INFRA": str(self.infra)}

    def tearDown(self):
        self.tmp.cleanup()

    def invoke(self, *args, input=b""):
        return subprocess.run([sys.executable, str(SCRIPT), *args], input=input, capture_output=True, env=self.env)

    def test_round_trip_and_modes(self):
        put = self.invoke("put", "app", input=b"# note\nexport ONE=1\nTWO=two\n")
        self.assertEqual(put.returncode, 0, put.stderr)
        self.assertIn(b"saved app: 2 keys", put.stderr)
        target = self.store / "app.env"
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.store.stat().st_mode), 0o700)
        got = self.invoke("get", "app")
        self.assertEqual(got.returncode, 0, got.stderr)
        self.assertEqual(got.stdout, b"# note\nexport ONE=1\nTWO=two\n")

    def test_invalid_name_and_traversal(self):
        for name in ("../bad", "UPPER", "", "a" * 65):
            result = self.invoke("put", name, input=b"X=secret\n")
            self.assertEqual(result.returncode, 2)
        self.assertFalse(self.store.exists())

    def test_invalid_line_keeps_old_file_and_hides_value(self):
        self.invoke("put", "app", input=b"OLD=ok\n")
        result = self.invoke("put", "app", input=b"NEW=super-secret-value\nbad line\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"line 2", result.stderr)
        self.assertNotIn(b"super-secret-value", result.stderr)
        self.assertEqual((self.store / "app.env").read_bytes(), b"OLD=ok\n")

    def test_duplicate_empty_and_oversize_rejected(self):
        duplicate = self.invoke("put", "app", input=b"X=one\nX=two\n")
        self.assertEqual(duplicate.returncode, 1)
        self.assertIn(b"line 2", duplicate.stderr)
        for data in (b"", b"X=" + b"x" * (1024 * 1024)):
            result = self.invoke("put", "app", input=data)
            self.assertEqual(result.returncode, 1)
        self.assertFalse((self.store / "app.env").exists())

    def test_backup_rotation(self):
        self.invoke("put", "app", input=b"X=0\n")
        history = self.store / ".history"
        history.mkdir()
        for number in range(11):
            (history / f"app.20200101T0000{number:02d}Z.env").write_bytes(b"old\n")
        result = self.invoke("put", "app", input=b"X=1\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        backups = sorted(history.glob("app.*.env"))
        self.assertEqual(len(backups), 10)
        generated = [item for item in backups if item.read_bytes() == b"X=0\n"]
        self.assertEqual(len(generated), 1)
        self.assertEqual(stat.S_IMODE(generated[0].stat().st_mode), 0o600)

    def test_unchanged_and_diff_hides_values(self):
        self.invoke("put", "app", input=b"KEEP=safe\nOLD=old\n")
        unchanged = self.invoke("put", "app", input=b"KEEP=safe\nOLD=old\n")
        self.assertEqual(unchanged.returncode, 0)
        self.assertEqual(unchanged.stderr, b"unchanged app\n")
        changed = self.invoke("put", "app", input=b"KEEP=new-secret\nNEW=also-secret\n")
        self.assertEqual(changed.returncode, 0, changed.stderr)
        self.assertIn(b"+NEW", changed.stderr)
        self.assertIn(b"-OLD", changed.stderr)
        self.assertIn(b"~KEEP", changed.stderr)
        self.assertNotIn(b"new-secret", changed.stderr)
        self.assertNotIn(b"also-secret", changed.stderr)

    def test_keys_diff_and_help(self):
        self.invoke("put", "app", input=b"KEEP=safe\nOLD=old\nCHANGED=old\n")
        keys = self.invoke("keys", "app")
        self.assertEqual(keys.returncode, 0, keys.stderr)
        self.assertEqual(keys.stdout, b"CHANGED\nKEEP\nOLD\n")
        missing = self.invoke("keys", "missing")
        self.assertEqual(missing.returncode, 1)
        self.assertEqual(missing.stderr, b"no such env: missing\n")
        same = self.invoke("diff", "app", input=b"KEEP=safe\nOLD=old\nCHANGED=old\n")
        self.assertEqual(same.returncode, 0, same.stderr)
        self.assertEqual(same.stdout, b"same\n")
        changed = self.invoke("diff", "app", input=b"KEEP=safe\nNEW=new\nCHANGED=new\n")
        self.assertEqual(changed.returncode, 1)
        self.assertEqual(changed.stdout, b"~CHANGED\n+NEW\n-OLD\n")
        self.assertNotIn(b"new", changed.stdout)
        absent = self.invoke("diff", "missing", input=b"Z=z\nA=a\n")
        self.assertEqual(absent.returncode, 1)
        self.assertEqual(absent.stdout, b"+A\n+Z\n")
        for args in (("--help",), ("put", "--help"), ("keys", "--help")):
            help_result = self.invoke(*args)
            self.assertEqual(help_result.returncode, 0, help_result.stderr)
            self.assertIn(b"env-keys", help_result.stdout)
            self.assertIn(b"envpush", help_result.stdout)

    def test_infra_change_needs_restart(self):
        changed = self.invoke("put", "infra", input=b"TOKEN=test-value\n")
        self.assertEqual(changed.returncode, 0, changed.stderr)
        self.assertIn(b"restart needed for services reading infra .env (ask orchestrator)\n", changed.stderr)
        unchanged = self.invoke("put", "infra", input=b"TOKEN=test-value\n")
        self.assertNotIn(b"restart needed", unchanged.stderr)

    def test_list_and_infra_override(self):
        self.invoke("put", "zebra", input=b"Z=1\n")
        self.invoke("put", "alpha", input=b"A=1\n")
        self.assertEqual(self.invoke("get").stdout, b"alpha\nzebra\n")
        put = self.invoke("put", "infra", input=b"TOKEN=test-value\n")
        self.assertEqual(put.returncode, 0, put.stderr)
        self.assertEqual(self.infra.read_bytes(), b"TOKEN=test-value\n")
        self.assertEqual(self.invoke("get", "infra").stdout, b"TOKEN=test-value\n")
        self.assertEqual(self.invoke("get").stdout, b"alpha\ninfra\nzebra\n")


if __name__ == "__main__":
    unittest.main()
