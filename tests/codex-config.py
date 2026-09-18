#!/usr/bin/env python3
"""Regression tests for the Codex public-whitelist reconciler."""

import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile

import tomlkit


repo = Path(os.environ.get("TEST_ROOT", Path(__file__).parents[1]))
spec = importlib.util.spec_from_file_location(
    "codex_config", repo / "scripts/reconcile-codex-config.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def expect_error(callback, text):
    try:
        callback()
        raise AssertionError(f"expected error containing {text!r}")
    except module.ReconcileError as error:
        assert text in str(error), error


baseline = tomlkit.parse(
    """model = "managed"
[analytics]
enabled = false
[agents]
max_concurrent_threads_per_session = 256
"""
)
live = tomlkit.parse(
    """# keep this comment
model = "local"
unmanaged = "preserve"
[analytics]
enabled = true
[projects."/private/project"]
trust_level = "trusted"
"""
)
updated = module.apply_toml(baseline, live)
rendered = tomlkit.dumps(updated)
assert '# keep this comment' in rendered
assert updated["model"] == "managed"
assert updated["analytics"]["enabled"] is False
assert updated["agents"]["max_concurrent_threads_per_session"] == 256
assert updated["unmanaged"] == "preserve"
assert updated["projects"]["/private/project"]["trust_level"] == "trusted"

# Removing a leaf from the baseline releases it instead of deleting live data.
released = tomlkit.parse('model = "managed"\n')
released_live = tomlkit.parse('model = "local"\nunmanaged = "preserve"\n')
module.apply_toml(released, released_live)
assert released_live["unmanaged"] == "preserve"

# Capture updates only the leaves already represented by the public baseline.
captured = module.capture_toml(
    tomlkit.parse('model = "old"\n[analytics]\nenabled = false\n'),
    tomlkit.parse('model = "new"\nsecret = "private"\n[analytics]\nenabled = true\n'),
)
assert captured["model"] == "new"
assert captured["analytics"]["enabled"] is True
assert "secret" not in captured
expect_error(
    lambda: module.capture_toml(
        tomlkit.parse('model = "old"\nmissing = true\n'),
        tomlkit.parse('model = "new"\n'),
    ),
    "managed live value is missing",
)

# JSON null is an explicit managed value, while unlisted commands and fields survive.
managed_keys = [{"command": "disabled", "key": None}]
live_keys = [
    {"command": "disabled", "key": "Command+D", "appMetadata": "preserve"},
    {"command": "application-owned", "key": "Command+U"},
]
applied_keys = module.apply_bindings(managed_keys, live_keys)
assert applied_keys[0] == {
    "command": "disabled",
    "key": None,
    "appMetadata": "preserve",
}
assert applied_keys[1] == live_keys[1]
captured_keys = module.capture_bindings(
    managed_keys, [{"command": "disabled", "key": "Fn"}, *live_keys[1:]]
)
assert captured_keys == [{"command": "disabled", "key": "Fn"}]
expect_error(
    lambda: module.validate_bindings(
        [{"command": "same", "key": "A"}, {"command": "same", "key": "B"}],
        "test",
    ),
    "duplicate command",
)

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    target = root / "config.toml"
    expected = module.current_fingerprint(target)
    data = b'model = "managed"\n'
    assert module.atomic_write(target, data, expected, 0o600)
    assert target.read_bytes() == data
    assert stat.S_IMODE(target.stat().st_mode) == 0o600
    unchanged = module.current_fingerprint(target)
    assert not module.atomic_write(target, data, unchanged, 0o600)

    stale = module.current_fingerprint(target)
    target.write_text('model = "concurrent"\n')
    expect_error(
        lambda: module.atomic_write(target, data, stale, 0o600),
        "changed concurrently",
    )

    link = root / "linked.toml"
    link.symlink_to(target)
    expect_error(lambda: module.read_regular(link), "non-regular file")

assert module.parse_toml(b"", "empty live config") == {}
expect_error(lambda: module.parse_toml(b"broken = [", "malformed"), "invalid TOML")

# Repository policy checks prevent accidental expansion into local/private state.
public_path = repo / "nix/modules/shared/ai-applications/codex-managed.toml"
public_text = public_path.read_text()
public = tomlkit.parse(public_text)
assert public["agents"]["max_concurrent_threads_per_session"] == 256
for forbidden in [
    "[projects",
    "[mcp_servers",
    "service_tier",
    "dictationDictionary",
    "localeOverride",
    "conversationDetailMode",
    "writable_roots",
    "/Users/",
]:
    assert forbidden not in public_text, forbidden

manifest = json.loads(
    (repo / "nix/modules/shared/ai-applications/codex-keybindings.json").read_text()
)
module.validate_bindings(manifest, "repository manifest")
assert len(manifest) == 13
assert all(not binding["command"].startswith("thread") for binding in manifest)
assert any(binding["key"] is None for binding in manifest)

home_module = (repo / "nix/modules/shared/ai-applications/home.nix").read_text()
assert 'entryAfter ["writeBoundary" "stowDotfiles"]' in home_module
