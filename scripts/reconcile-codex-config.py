#!/usr/bin/env python3
"""Reconcile an explicit public Codex whitelist with app-owned live files."""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
from typing import Any, Iterable

import tomlkit
from tomlkit.container import Container
from tomlkit.exceptions import ParseError
from tomlkit.items import Table


class ReconcileError(RuntimeError):
    pass


MISSING = object()


def _is_table(value: Any) -> bool:
    return isinstance(value, (Container, Table))


def leaf_paths(value: Any, prefix: tuple[str, ...] = ()) -> Iterable[tuple[str, ...]]:
    if _is_table(value):
        for key, child in value.items():
            yield from leaf_paths(child, prefix + (str(key),))
        return
    if not prefix:
        raise ReconcileError("the managed TOML baseline must contain at least one value")
    yield prefix


def get_path(document: Any, path: tuple[str, ...]) -> Any:
    current = document
    for component in path:
        if not _is_table(current) or component not in current:
            return MISSING
        current = current[component]
    return current


def set_path(document: Any, path: tuple[str, ...], value: Any) -> None:
    current = document
    for component in path[:-1]:
        existing = current.get(component, MISSING)
        if existing is MISSING:
            current[component] = tomlkit.table()
            existing = current[component]
        if not _is_table(existing):
            raise ReconcileError(
                f"cannot manage {'.'.join(path)} because {component} is not a table"
            )
        current = existing
    current[path[-1]] = copy.deepcopy(value)


def comparable(value: Any) -> Any:
    return value.unwrap() if hasattr(value, "unwrap") else value


def apply_toml(baseline: Any, live: Any) -> Any:
    for path in leaf_paths(baseline):
        set_path(live, path, get_path(baseline, path))
    return live


def capture_toml(baseline: Any, live: Any) -> Any:
    for path in list(leaf_paths(baseline)):
        value = get_path(live, path)
        if value is MISSING:
            raise ReconcileError(f"managed live value is missing: {'.'.join(path)}")
        set_path(baseline, path, value)
    return baseline


def toml_drift(baseline: Any, live: Any) -> list[str]:
    drift = []
    for path in leaf_paths(baseline):
        expected = get_path(baseline, path)
        actual = get_path(live, path)
        if actual is MISSING or comparable(actual) != comparable(expected):
            drift.append(".".join(path))
    return drift


def validate_bindings(value: Any, label: str) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        raise ReconcileError(f"{label} must contain a JSON array")
    seen = set()
    result = []
    for index, binding in enumerate(value):
        if not isinstance(binding, dict) or not isinstance(binding.get("command"), str):
            raise ReconcileError(f"{label} entry {index} must have a string command")
        command = binding["command"]
        if command in seen:
            raise ReconcileError(f"duplicate command in {label}: {command}")
        seen.add(command)
        result.append(binding)
    return result


def apply_bindings(managed: list[dict[str, Any]], live: list[dict[str, Any]]) -> list[dict[str, Any]]:
    managed = validate_bindings(managed, "managed keybindings")
    live = copy.deepcopy(validate_bindings(live, "live keybindings"))
    indexes = {binding["command"]: index for index, binding in enumerate(live)}
    for binding in managed:
        command = binding["command"]
        if command not in indexes:
            indexes[command] = len(live)
            live.append(copy.deepcopy(binding))
            continue
        target = live[indexes[command]]
        for key, value in binding.items():
            target[key] = copy.deepcopy(value)
    return live


def capture_bindings(managed: list[dict[str, Any]], live: list[dict[str, Any]]) -> list[dict[str, Any]]:
    managed = copy.deepcopy(validate_bindings(managed, "managed keybindings"))
    live_by_command = {
        binding["command"]: binding
        for binding in validate_bindings(live, "live keybindings")
    }
    for binding in managed:
        command = binding["command"]
        if command not in live_by_command:
            raise ReconcileError(f"managed live keybinding is missing: {command}")
        live_binding = live_by_command[command]
        for key in list(binding):
            if key not in live_binding:
                raise ReconcileError(f"managed live keybinding field is missing: {command}.{key}")
            binding[key] = copy.deepcopy(live_binding[key])
    return managed


def bindings_drift(managed: list[dict[str, Any]], live: list[dict[str, Any]]) -> list[str]:
    managed = validate_bindings(managed, "managed keybindings")
    live_by_command = {
        binding["command"]: binding
        for binding in validate_bindings(live, "live keybindings")
    }
    drift = []
    for binding in managed:
        command = binding["command"]
        actual = live_by_command.get(command)
        if actual is None or any(actual.get(key, MISSING) != value for key, value in binding.items()):
            drift.append(command)
    return drift


def _fingerprint(path: Path, data: bytes, metadata: os.stat_result) -> tuple[Any, ...]:
    return (
        True,
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_size,
        metadata.st_mtime_ns,
        hashlib.sha256(data).digest(),
    )


def read_regular(path: Path, *, missing: bytes | None = None) -> tuple[bytes, tuple[Any, ...]]:
    try:
        before = path.lstat()
    except FileNotFoundError:
        if missing is None:
            raise ReconcileError(f"required file is missing: {path}")
        return missing, (False,)
    if not stat.S_ISREG(before.st_mode):
        raise ReconcileError(f"refusing non-regular file: {path}")
    data = path.read_bytes()
    after = path.lstat()
    if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
        after.st_dev,
        after.st_ino,
        after.st_size,
        after.st_mtime_ns,
    ):
        raise ReconcileError(f"file changed while being read: {path}")
    return data, _fingerprint(path, data, after)


def current_fingerprint(path: Path) -> tuple[Any, ...]:
    _, fingerprint = read_regular(path, missing=b"")
    return fingerprint


def atomic_write(path: Path, data: bytes, expected: tuple[Any, ...], mode: int) -> bool:
    current_data, current = read_regular(path, missing=b"")
    if current != expected:
        raise ReconcileError(f"file changed concurrently: {path}")
    if current[0] and current_data == data:
        if stat.S_IMODE(path.stat().st_mode) != mode:
            path.chmod(mode)
        return False
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.parent.is_symlink() or not path.parent.is_dir():
        raise ReconcileError(f"refusing unsafe parent directory: {path.parent}")
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        if current_fingerprint(path) != expected:
            raise ReconcileError(f"file changed concurrently: {path}")
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


def parse_toml(data: bytes, label: str, *, require_values: bool = False) -> Any:
    try:
        document = tomlkit.parse(data.decode())
        if require_values:
            list(leaf_paths(document))
        return document
    except (UnicodeDecodeError, ParseError, ReconcileError) as error:
        raise ReconcileError(f"invalid TOML in {label}: {error}") from error


def parse_json(data: bytes, label: str) -> list[dict[str, Any]]:
    try:
        return validate_bindings(json.loads(data), label)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ReconcileError(f"invalid JSON in {label}: {error}") from error


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()


def reconcile(args: argparse.Namespace) -> int:
    # abspath preserves a final symlink so read_regular can reject it.
    baseline_path = Path(os.path.abspath(args.baseline.expanduser()))
    manifest_path = Path(os.path.abspath(args.keybindings_manifest.expanduser()))
    config_path = Path(os.path.abspath(args.config.expanduser()))
    keybindings_path = Path(os.path.abspath(args.keybindings.expanduser()))

    baseline_data, baseline_state = read_regular(baseline_path)
    manifest_data, manifest_state = read_regular(manifest_path)
    live_toml_data, live_toml_state = read_regular(config_path, missing=b"")
    live_json_data, live_json_state = read_regular(keybindings_path, missing=b"[]\n")

    baseline = parse_toml(baseline_data, str(baseline_path), require_values=True)
    managed_bindings = parse_json(manifest_data, str(manifest_path))
    live = parse_toml(live_toml_data, str(config_path)) if live_toml_state[0] else tomlkit.document()
    live_bindings = parse_json(live_json_data, str(keybindings_path))

    if args.action == "diff":
        toml_changes = toml_drift(baseline, live)
        binding_changes = bindings_drift(managed_bindings, live_bindings)
        for path in toml_changes:
            print(f"config: {path}")
        for command in binding_changes:
            print(f"keybinding: {command}")
        if not toml_changes and not binding_changes:
            print("Codex managed configuration is in sync.")
        return 1 if toml_changes or binding_changes else 0

    if args.action == "apply":
        updated_toml = tomlkit.dumps(apply_toml(baseline, live)).encode()
        updated_bindings = json_bytes(apply_bindings(managed_bindings, live_bindings))
        # Parse the complete outputs before replacing either live file.
        parse_toml(updated_toml, "generated live config")
        parse_json(updated_bindings, "generated live keybindings")
        changed_config = atomic_write(config_path, updated_toml, live_toml_state, 0o600)
        changed_keys = atomic_write(keybindings_path, updated_bindings, live_json_state, 0o600)
        print(f"Codex configuration reconciled ({int(changed_config) + int(changed_keys)} file(s) changed).")
        return 0

    updated_baseline = tomlkit.dumps(capture_toml(baseline, live)).encode()
    updated_manifest = json_bytes(capture_bindings(managed_bindings, live_bindings))
    parse_toml(updated_baseline, "captured managed config")
    parse_json(updated_manifest, "captured managed keybindings")
    changed_baseline = atomic_write(baseline_path, updated_baseline, baseline_state, 0o644)
    changed_manifest = atomic_write(manifest_path, updated_manifest, manifest_state, 0o644)
    print(f"Codex whitelist captured ({int(changed_baseline) + int(changed_manifest)} file(s) changed).")
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("action", choices=("apply", "capture", "diff"))
    result.add_argument("--baseline", type=Path, required=True)
    result.add_argument("--keybindings-manifest", type=Path, required=True)
    result.add_argument("--config", type=Path, default=Path("~/.codex/config.toml"))
    result.add_argument("--keybindings", type=Path, default=Path("~/.codex/keybindings.json"))
    return result


def main() -> int:
    try:
        return reconcile(parser().parse_args())
    except (OSError, ReconcileError) as error:
        print(f"codex-config: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
