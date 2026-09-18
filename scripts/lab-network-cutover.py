#!/usr/bin/env python3
"""Fail-closed operator shell for the two-phase lab network cutover."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import stat
import subprocess
import sys
import tempfile
import time
from typing import Any


READ_ONLY_CAPTURE = (
    "set -eu; "
    "uci -q export network; "
    "uci -q export dhcp; "
    "uci -q export firewall; "
    "ip -j address show; "
    "ip -j route show table all; "
    "ubus call system board; "
    "service dnsmasq status; "
    "service odhcpd status; "
    "nft -j list ruleset"
)


class Refusal(RuntimeError):
    pass


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise Refusal(f"cannot read valid JSON from {path}: {error}") from error


def secure_regular_file(path: Path) -> None:
    try:
        info = path.lstat()
    except OSError as error:
        raise Refusal(f"required local device mapping is unavailable: {path}") from error
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise Refusal(f"device mapping must be a regular, non-symlink file: {path}")
    if info.st_uid != os.getuid():
        raise Refusal("device mapping must be owned by the current user")
    if stat.S_IMODE(info.st_mode) != 0o600:
        raise Refusal("device mapping permissions must be exactly 0600")


def validate_overlay(path: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    secure_regular_file(path)
    data = load_json(path)
    if not isinstance(data, dict) or set(data) != {"schemaVersion", "reservations"}:
        raise Refusal("device mapping must contain only schemaVersion and reservations")
    if data["schemaVersion"] != 1 or not isinstance(data["reservations"], dict):
        raise Refusal("unsupported device mapping schema")
    expected = set(manifest["reservationRefs"])
    actual = set(data["reservations"])
    if actual != expected:
        raise Refusal("device mapping references do not exactly match the manifest")
    values: list[str] = []
    for ref, item in data["reservations"].items():
        if not isinstance(item, dict) or set(item) != {"mac"} or not isinstance(item["mac"], str):
            raise Refusal(f"reservation {ref} must contain exactly one string mac field")
        compact = item["mac"].lower()
        parts = compact.split(":")
        if len(parts) != 6 or any(len(part) != 2 or any(c not in "0123456789abcdef" for c in part) for part in parts):
            raise Refusal(f"reservation {ref} has an invalid MAC address")
        values.append(compact)
    if len(values) != len(set(values)):
        raise Refusal("device mapping contains duplicate MAC addresses")
    return data


def atomic_private_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(canonical(value) + b"\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def paths() -> tuple[Path, Path, Path]:
    home = Path.home()
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    state = Path(os.environ.get("XDG_STATE_HOME", home / ".local/state"))
    overlay = Path(os.environ.get("LAB_CUTOVER_DEVICES", config / "dotfiles/lab-network-cutover/devices.json"))
    root = Path(os.environ.get("LAB_CUTOVER_STATE", state / "dotfiles/lab-network-cutover"))
    manifest_value = os.environ.get("LAB_CUTOVER_MANIFEST")
    if not manifest_value:
        raise Refusal("LAB_CUTOVER_MANIFEST is not set; use the packaged Nix app")
    manifest_path = Path(manifest_value)
    return overlay, root, manifest_path


def capture(target: str) -> dict[str, Any]:
    override = os.environ.get("LAB_CUTOVER_CAPTURE_COMMAND")
    if override:
        command = [override, target, READ_ONLY_CAPTURE]
    else:
        command = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", f"root@{target}", READ_ONLY_CAPTURE]
    result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=45)
    if result.returncode != 0:
        raise Refusal("read-only Charon capture failed; no mutation is permitted")
    return {
        "commandPolicy": "read-only-v1",
        "target": target,
        "sha256": hashlib.sha256(result.stdout.encode()).hexdigest(),
        "bytes": len(result.stdout.encode()),
    }


def pointer_path(root: Path, phase: str) -> Path:
    return root / f"{phase}-prepared.json"


def stored_receipt(root: Path, run_id: str) -> Path:
    return root / "runs" / run_id / "receipt.json"


def prepare(phase: str, manifest: dict[str, Any], overlay_path: Path, root: Path, target: str) -> None:
    if phase == "phase2":
        raise Refusal("phase2 prepare is locked until the verified phase1 confirm transition is implemented")
    overlay = validate_overlay(overlay_path, manifest)
    evidence = capture(target)
    run_id = f"{int(time.time())}-{secrets.token_hex(4)}"
    receipt = {
        "schemaVersion": 1,
        "runId": run_id,
        "phase": phase,
        "state": f"{phase}-prepared",
        "preparedAt": int(time.time()),
        "manifestDigest": digest(manifest),
        "overlayDigest": digest(overlay),
        "evidence": evidence,
        "mutationAdapterReady": bool(manifest.get("mutationAdapterReady")),
    }
    receipt_file = stored_receipt(root, run_id)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    (root / "runs").mkdir(exist_ok=True, mode=0o700)
    os.chmod(root / "runs", 0o700)
    receipt_file.parent.mkdir(exist_ok=False, mode=0o700)
    atomic_private_json(receipt_file, receipt)
    atomic_private_json(pointer_path(root, phase), {"runId": run_id, "receiptDigest": digest(receipt)})
    print(f"{phase} prepared; receipt {receipt_file}")
    if not receipt["mutationAdapterReady"]:
        print("live mutation remains locked pending verified Charon capture and fencing adapter")


def verify_receipt(phase: str, manifest: dict[str, Any], overlay_path: Path, root: Path) -> dict[str, Any]:
    overlay = validate_overlay(overlay_path, manifest)
    pointer = load_json(pointer_path(root, phase))
    if not isinstance(pointer, dict) or set(pointer) != {"runId", "receiptDigest"}:
        raise Refusal("prepared receipt pointer is invalid")
    run_id = pointer["runId"]
    if not isinstance(run_id, str) or "/" in run_id or run_id in ("", ".", ".."):
        raise Refusal("prepared receipt run identifier is invalid")
    receipt = load_json(stored_receipt(root, run_id))
    if pointer["receiptDigest"] != digest(receipt):
        raise Refusal("immutable prepared receipt was modified")
    if receipt.get("phase") != phase or receipt.get("state") != f"{phase}-prepared":
        raise Refusal("prepared receipt is absent or has an invalid lifecycle state")
    if receipt.get("manifestDigest") != digest(manifest) or receipt.get("overlayDigest") != digest(overlay):
        raise Refusal("prepared inputs drifted; run prepare again explicitly")
    return receipt


def status(phase: str, manifest: dict[str, Any], overlay_path: Path, root: Path) -> None:
    if not pointer_path(root, phase).exists():
        for candidate in (root / "runs").glob("*/receipt.json"):
            try:
                orphan = load_json(candidate)
            except Refusal as error:
                raise Refusal("RecoveryRequired: an unreadable receipt exists without a phase pointer") from error
            if not isinstance(orphan, dict):
                raise Refusal("RecoveryRequired: an invalid receipt exists without a phase pointer")
            if orphan.get("phase") == phase:
                raise Refusal("RecoveryRequired: prepared receipts exist but the phase pointer is missing")
        print(json.dumps({"phase": phase, "state": "idle", "safe": True, "ready": False}, sort_keys=True))
        return
    try:
        receipt = verify_receipt(phase, manifest, overlay_path, root)
    except Refusal as error:
        raise Refusal(f"RecoveryRequired: {error}") from error
    print(json.dumps({
        "phase": phase,
        "state": receipt["state"],
        "safe": True,
        "ready": False,
        "mutationAdapterReady": receipt["mutationAdapterReady"],
        "preparedAt": receipt["preparedAt"],
    }, sort_keys=True))


def guarded_mutation(action: str, phase: str, manifest: dict[str, Any], overlay_path: Path, root: Path) -> None:
    receipt = verify_receipt(phase, manifest, overlay_path, root)
    if not manifest.get("mutationAdapterReady") or not receipt.get("mutationAdapterReady"):
        raise Refusal(
            f"{action} refused: mutation adapter is intentionally locked until topology, backups, "
            "persistent watchdogs, DHCP fencing, and rollback probes are live-verified"
        )
    raise Refusal(f"{action} refused: no verified mutating adapter is packaged")


def main() -> int:
    parser = argparse.ArgumentParser(prog="lab-network-cutover")
    parser.add_argument("phase", choices=("phase1", "phase2"))
    parser.add_argument("action", choices=("prepare", "apply", "status", "confirm", "rollback"))
    parser.add_argument("--charon", default=os.environ.get("LAB_CUTOVER_CHARON"))
    args = parser.parse_args()
    try:
        overlay_path, root, manifest_path = paths()
        manifest = load_json(manifest_path)
        target = args.charon or manifest["migration"]["recoveryAddress"]
        if args.action == "prepare":
            prepare(args.phase, manifest, overlay_path, root, target)
        elif args.action == "status":
            status(args.phase, manifest, overlay_path, root)
        else:
            guarded_mutation(args.action, args.phase, manifest, overlay_path, root)
        return 0
    except (Refusal, subprocess.TimeoutExpired) as error:
        print(f"refused: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
