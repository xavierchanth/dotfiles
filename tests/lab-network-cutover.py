#!/usr/bin/env python3

import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(os.environ.get("TEST_ROOT", Path(__file__).resolve().parents[1]))
SCRIPT = Path(os.environ.get("LAB_CUTOVER_BIN", ROOT / "scripts/lab-network-cutover.py"))
MANIFEST = Path(os.environ.get("LAB_CUTOVER_MANIFEST_TEST", ""))


class CutoverTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.config = self.root / "config"
        self.state = self.root / "state"
        self.config.mkdir()
        self.capture_log = self.root / "capture.log"
        self.capture = self.root / "capture"
        self.capture.write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$2\" > \"$LAB_CAPTURE_LOG\"\nprintf 'synthetic read-only evidence\\n'\n"
        )
        self.capture.chmod(0o700)
        if MANIFEST.is_file():
            self.manifest = MANIFEST
        else:
            self.manifest = self.root / "manifest.json"
            nix = subprocess.run(
                ["nix", "eval", "--json", "--file", str(ROOT / "nix/openwrt/cutover.nix")],
                check=True, capture_output=True, text=True,
            )
            self.manifest.write_text(nix.stdout)
        manifest = json.loads(self.manifest.read_text())
        reservations = {
            ref: {"mac": f"02:00:00:00:00:{index:02x}"}
            for index, ref in enumerate(manifest["reservationRefs"], 1)
        }
        self.devices = self.config / "dotfiles/lab-network-cutover/devices.json"
        self.devices.parent.mkdir(parents=True)
        self.devices.write_text(json.dumps({"schemaVersion": 1, "reservations": reservations}))
        self.devices.chmod(0o600)
        self.env = os.environ | {
            "XDG_CONFIG_HOME": str(self.config),
            "XDG_STATE_HOME": str(self.state),
            "LAB_CUTOVER_MANIFEST": str(self.manifest),
            "LAB_CUTOVER_CAPTURE_COMMAND": str(self.capture),
            "LAB_CAPTURE_LOG": str(self.capture_log),
            "PYTHONDONTWRITEBYTECODE": "1",
        }

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args):
        command = [str(SCRIPT), *args] if SCRIPT.name == "lab-network-cutover" else [sys.executable, str(SCRIPT), *args]
        return subprocess.run(command, env=self.env, capture_output=True, text=True)

    def test_prepare_is_read_only_and_private(self):
        result = self.run_cli("phase1", "prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        capture = self.capture_log.read_text()
        for forbidden in ("uci set", "uci commit", "service network restart", "reboot"):
            self.assertNotIn(forbidden, capture)
        pointer = json.loads((self.state / "dotfiles/lab-network-cutover/phase1-prepared.json").read_text())
        receipt = self.state / "dotfiles/lab-network-cutover/runs" / pointer["runId"] / "receipt.json"
        self.assertEqual(stat.S_IMODE(receipt.stat().st_mode), 0o600)
        text = receipt.read_text()
        self.assertNotIn("02:00:00", text)
        self.assertIn("overlayDigest", text)

    def test_apply_is_fail_closed(self):
        self.assertEqual(self.run_cli("phase1", "prepare").returncode, 0)
        result = self.run_cli("phase1", "apply")
        self.assertEqual(result.returncode, 2)
        self.assertIn("mutation adapter is intentionally locked", result.stderr)

    def test_overlay_drift_invalidates_receipt(self):
        self.assertEqual(self.run_cli("phase1", "prepare").returncode, 0)
        data = json.loads(self.devices.read_text())
        data["reservations"]["hades-lan"]["mac"] = "02:00:00:00:00:55"
        self.devices.write_text(json.dumps(data))
        self.devices.chmod(0o600)
        result = self.run_cli("phase1", "apply")
        self.assertEqual(result.returncode, 2)
        self.assertIn("drifted", result.stderr)

    def test_rejects_insecure_or_symlink_overlay(self):
        self.devices.chmod(0o644)
        self.assertEqual(self.run_cli("phase1", "prepare").returncode, 2)
        self.devices.chmod(0o600)
        real = self.devices.with_name("real.json")
        self.devices.rename(real)
        self.devices.symlink_to(real)
        self.assertEqual(self.run_cli("phase1", "prepare").returncode, 2)

    def test_rejects_duplicate_mac(self):
        data = json.loads(self.devices.read_text())
        data["reservations"]["poseidon-lan"] = data["reservations"]["hades-lan"]
        self.devices.write_text(json.dumps(data))
        self.devices.chmod(0o600)
        self.assertEqual(self.run_cli("phase1", "prepare").returncode, 2)

    def test_status_does_not_capture_or_mutate(self):
        result = self.run_cli("phase2", "status")
        self.assertEqual(result.returncode, 0)
        self.assertFalse(self.capture_log.exists())
        self.assertIn('"state": "idle"', result.stdout)

    def test_phase2_requires_phase1_stable(self):
        state_root = self.state / "dotfiles/lab-network-cutover"
        state_root.mkdir(parents=True)
        (state_root / "phase1-stable.json").write_text("garbage")
        result = self.run_cli("phase2", "prepare")
        self.assertEqual(result.returncode, 2)
        self.assertIn("verified phase1 confirm", result.stderr)

    def test_corrupt_pointer_is_recovery_required(self):
        self.assertEqual(self.run_cli("phase1", "prepare").returncode, 0)
        pointer = self.state / "dotfiles/lab-network-cutover/phase1-prepared.json"
        pointer.write_text("{}")
        pointer.chmod(0o600)
        result = self.run_cli("phase1", "status")
        self.assertEqual(result.returncode, 2)
        self.assertIn("RecoveryRequired", result.stderr)

    def test_missing_pointer_with_orphan_receipt_is_recovery_required(self):
        self.assertEqual(self.run_cli("phase1", "prepare").returncode, 0)
        pointer = self.state / "dotfiles/lab-network-cutover/phase1-prepared.json"
        pointer.unlink()
        result = self.run_cli("phase1", "status")
        self.assertEqual(result.returncode, 2)
        self.assertIn("RecoveryRequired", result.stderr)


if __name__ == "__main__":
    unittest.main()
