import hashlib
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(os.environ["TEST_ROOT"])
validator = root / "scripts/lab-runtime-state.py"
runtime_identity = "runtime-identity-0001"


def write(path, value, mode=0o600):
    path.write_text(json.dumps(value), encoding="utf-8")
    path.chmod(mode)


def run(*args, succeeds=True):
    command = [sys.executable, validator, *args]
    command.extend(["--expected-gid", str(os.getegid())])
    if args[0] in {"dhcp", "confirm", "activate"}:
        command.extend([
            "--runtime-identity", runtime_identity,
            "--receipt", str(prepared_receipt),
        ])
    if args[0] in {"confirm", "activate"}:
        command.extend(["--transaction-id", "transaction-confirm-0001", "--controller-pid", str(os.getpid())])
    if args[0] == "activate":
        command.append("--allow-pending")
    result = subprocess.run(command, text=True, capture_output=True)
    assert (result.returncode == 0) == succeeds, result.stderr
    return result.stdout


with tempfile.TemporaryDirectory() as directory:
    tmp = pathlib.Path(directory)
    uid = str(os.getuid())
    intent = tmp / "intent.json"
    overlay = tmp / "overlay.json"
    authority = tmp / "authority.json"
    prepared_receipt = tmp / "prepared-receipt.json"
    state = tmp / "state.json"
    write(intent, {"eris": {"address": "192.168.17.5"}, "hades": {"address": "192.168.17.2"}})
    bindings = {"version": 1, "bindings": {"eris": {"macAddress": "02:AA:00:00:00:05"}, "hades": {"macAddress": "02:aa:00:00:00:02"}}}
    write(overlay, bindings)
    overlay_sha = hashlib.sha256(overlay.read_bytes()).hexdigest()
    prepared = {"version": 1, "authority": "hades", "phase": "phase2", "transition": "charon-to-hades", "charonDhcpSilent": True, "preparedState": "prepared-state-0001", "overlaySha256": overlay_sha, "runtimeIdentity": runtime_identity, "expiresAt": 200}
    write(prepared_receipt, prepared)
    receipt_sha = hashlib.sha256(prepared_receipt.read_bytes()).hexdigest()
    receipt = prepared | {"sourceReceiptSha256": receipt_sha, "activationState": "active", "transactionId": "transaction-0001", "controllerPid": os.getpid()}
    write(authority, receipt)
    missing = tmp / "missing.json"
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(missing), "--authority", str(authority), succeeds=False)
    output = run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority))
    assert "02:aa:00:00:00:05" in output
    write(authority, receipt | {"expiresAt": 201})
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    write(authority, receipt | {"runtimeIdentity": "previous-boot-0001"})
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    write(authority, receipt)
    prepared_receipt.write_text("{partial", encoding="utf-8")
    prepared_receipt.chmod(0o600)
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    prepared_receipt.unlink()
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    write(prepared_receipt, prepared)
    run("dhcp", "--expected-uid", uid, "--now", "201", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    write(authority, receipt | {"expiresAt": None})
    # Confirmation cannot outlive the protected source receipt across a later
    # watchdog cycle or reboot-time preparation.
    run("dhcp", "--expected-uid", uid, "--now", "201", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    write(authority, {"version": 1, "authority": "hades"})
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    authority.write_text("{partial", encoding="utf-8")
    authority.chmod(0o600)
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    authority.unlink()
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    write(authority, receipt)
    changed_bindings = bindings | {"bindings": bindings["bindings"] | {"eris": {"macAddress": "02:aa:00:00:00:06"}}}
    write(overlay, changed_bindings)
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    write(overlay, bindings)
    write(authority, receipt | {"transition": "hades-to-charon"})
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    write(authority, receipt | {"charonDhcpSilent": False})
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    write(authority, receipt | {"preparedState": "different-state-0002"})
    run("confirm", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), "--prepared-state", "prepared-state-0001", succeeds=False)
    write(overlay, {"version": 1, "bindings": {"eris": bindings["bindings"]["eris"]}})
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    write(overlay, bindings)
    duplicate = bindings | {"bindings": bindings["bindings"] | {"eris": {"macAddress": "02:AA:00:00:00:02"}}}
    write(overlay, duplicate)
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    write(overlay, bindings, 0o644)
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
    other_gids = [gid for gid in os.getgroups() if gid != os.getegid()]
    if other_gids:
        write(overlay, bindings)
        try:
            os.chown(overlay, -1, other_gids[0])
        except PermissionError:
            pass
        else:
            run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), succeeds=False)
            os.chown(overlay, -1, os.getegid())
    write(overlay, bindings)
    write(authority, receipt)
    run("confirm", "--expected-uid", uid, "--now", "201", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), "--prepared-state", "prepared-state-0001", succeeds=False)
    assert json.loads(authority.read_text(encoding="utf-8"))["expiresAt"] == 200
    run("confirm", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), "--prepared-state", "wrong-prepared-state", succeeds=False)
    run("confirm", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), "--prepared-state", "prepared-state-0001")
    run("activate", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority))
    confirmed = json.loads(authority.read_text(encoding="utf-8"))
    assert confirmed["expiresAt"] is None
    assert authority.stat().st_mode & 0o777 == 0o600
    assert authority.stat().st_gid == os.getegid()
    assert not list(tmp.glob(".dhcp-authority.*"))

    spec = importlib.util.spec_from_file_location("lab_runtime_state", validator)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    write(authority, receipt)
    original_replace = module.os.replace
    module.os.replace = lambda *_: (_ for _ in ()).throw(OSError("simulated interruption"))
    try:
        try:
            module.atomic_write_json(str(authority), receipt | {"expiresAt": None})
        except OSError:
            pass
        else:
            raise AssertionError("interrupted atomic update unexpectedly succeeded")
    finally:
        module.os.replace = original_replace
    assert json.loads(authority.read_text(encoding="utf-8"))["expiresAt"] == 200
    assert not list(tmp.glob(".dhcp-authority.*"))

    # A crash-created partial sibling must never be mistaken for authority, and
    # a subsequent confirmation must replace the canonical file atomically.
    partial = tmp / ".dhcp-authority.partial"
    partial.write_text("{\"version\":1", encoding="utf-8")
    partial.chmod(0o600)
    run("dhcp", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority))
    run("confirm", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority), "--prepared-state", "prepared-state-0001")
    run("activate", "--expected-uid", uid, "--now", "100", "--intent", str(intent), "--overlay", str(overlay), "--authority", str(authority))
    assert json.loads(authority.read_text(encoding="utf-8"))["expiresAt"] is None
    assert partial.read_text(encoding="utf-8") == '{"version":1'
    write(state, {"version": 1, "service": "svc:lab", "resolverAddress": "192.0.2.2", "address": "192.0.2.3", "expiresAt": 200, "nodeIdentity": "node-identity", "desiredConfigSha256": "a" * 64})
    run("tailnet", "--expected-uid", uid, "--now", "100", "--state", str(state))
    run("tailnet", "--expected-uid", uid, "--now", "201", "--state", str(state), succeeds=False)


# The lifecycle controller is generated from this Nix shell. These source
# contracts supplement validator fault injection by pinning the fencing and
# lock ordering which prevents control-plane races and fail-open recovery.
module_source = (root / "nix/modules/nixos/lab-dns-dhcp/system.nix").read_text(encoding="utf-8")
authority_start = module_source.index('name = "lab-dhcp-authority";')
watchdog_start = module_source.index('name = "lab-dhcp-authority-watchdog";')
authority_shell = module_source[authority_start:watchdog_start]
watchdog_shell = module_source[watchdog_start:]

assert authority_shell.index('exec 8>"$state_dir/operation.lock"') < authority_shell.index('exec 9>"$state_dir/render.lock"')
assert authority_shell.index("flock -u 9") < authority_shell.index('"$systemctl_cmd" restart lab-dns-dhcp.service')
assert authority_shell.index("fence_service ||") < authority_shell.index("revoke_locked ||") < authority_shell.index('"$systemctl_cmd" start lab-dns-dhcp.service')
assert authority_shell.index("schedule_deadline \"$expires_at\"") < authority_shell.index("\n          activate_dhcp")
assert "if test \"$expires_at\" -gt \"$receipt_expires\"; then expires_at=$receipt_expires; fi" in authority_shell
assert "trap transition_failed ERR" in authority_shell

watchdog_stop = watchdog_shell.index('"$systemctl_cmd" stop --no-block lab-dns-dhcp.service')
watchdog_revoke = watchdog_shell.index('mv "$authority" "$rejected"')
watchdog_restart = watchdog_shell.index('"$systemctl_cmd" start lab-dns-dhcp.service')
assert watchdog_shell.index('exec 8>"$state_dir/operation.lock"') < watchdog_shell.index('exec 9>"$state_dir/render.lock"')
assert watchdog_stop < watchdog_revoke < watchdog_restart
assert "service remains fenced" in watchdog_shell
assert 'grep -qx dns-only "$runtime_state"' in watchdog_shell
assert 'test "$(stat -c %U:%G:%a "$receipt")" = root:root:600' in authority_shell
assert 'test "$(stat -c %U:%G:%a "$overlay")" = root:root:600' in authority_shell
