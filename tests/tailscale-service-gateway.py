#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


root = Path(__file__).resolve().parents[1]
controller = Path(os.environ.get("SVC_LAB_CONTROLLER", root / "scripts/tailscale-service-gateway.py"))


MOCK = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import sys
import time

state_path = Path(os.environ["MOCK_STATE"])
state = json.loads(state_path.read_text())
name = Path(sys.argv[0]).name
args = sys.argv[1:]
state.setdefault("calls", []).append([name, *args])

def save():
    state_path.write_text(json.dumps(state))

if state.get("fail_cli") == name or state.get("fail_cli") == "all":
    save()
    sys.exit(1)

if name == "curl":
    save()
    if not state.get("caddy_healthy", True):
        sys.exit(7)
    print(state.get("gateway_http_status", "200"), end="")
    sys.exit(0)

if name == "systemctl":
    if args[:2] == ["is-active", "--quiet"]:
        unit = args[2]
        active = state.get("caddy_active", True) if unit == "caddy.service" else state.get("dns_active", True)
        save()
        sys.exit(0 if active else 3)
    if args[:1] == ["stop"]:
        state["dns_active"] = False
    if args[:1] == ["restart"]:
        state["dns_active"] = True
        state["dns_restarts"] = state.get("dns_restarts", 0) + 1
    save()
    sys.exit(0)

if args[:2] == ["status", "--json"]:
    if "status_value" in state:
        save()
        print(json.dumps(state["status_value"]))
        sys.exit(0)
    capmap = {"service-host": ["svc:lab"]} if state.get("advertised", False) else {}
    primary = [state["tailvip"] + "/32"] if state.get("advertised", False) and state.get("approved", False) else []
    value = {
        "BackendState": state.get("backend", "Running"),
        "Self": {
            "ID": state.get("node_identity", "node-1"),
            "TailscaleIPs": [state.get("resolver", "198.51.100.2")],
            "CapMap": capmap,
            "PrimaryRoutes": primary,
        },
    }
    save()
    print(json.dumps(value))
    sys.exit(0)

if args[:3] == ["serve", "set-config", "--all"]:
    time.sleep(state.get("delay", 0))
    state["live_config"] = json.loads(Path(args[3]).read_text())
    if state.get("drift_after_apply"):
        state["live_config"]["services"]["svc:lab"]["endpoints"]["tcp:443"] = "tcp://127.0.0.1:9999"
    save()
    sys.exit(0)

if args[:2] == ["serve", "advertise"]:
    state["advertised"] = True
    save()
    sys.exit(0)

if args[:3] == ["serve", "get-config", "--all"]:
    Path(args[3]).write_text(json.dumps(state.get("live_config", {})))
    save()
    sys.exit(0)

if args[:2] == ["serve", "drain"]:
    state["advertised"] = False
    save()
    sys.exit(0)

save()
sys.exit(64)
'''


def write_json(path, value):
    path.write_text(json.dumps(value))
    path.chmod(0o600)


with tempfile.TemporaryDirectory(prefix="svc-lab-tests.") as raw_tmp:
    tmp = Path(raw_tmp)
    bin_dir = tmp / "bin"
    bin_dir.mkdir()
    for name in ("tailscale", "systemctl", "curl"):
        path = bin_dir / name
        path.write_text(MOCK)
        path.chmod(0o755)

    desired = {
        "version": "0.0.1",
        "services": {"svc:lab": {"advertised": True, "endpoints": {"tcp:443": "tcp://127.0.0.1:8443"}}},
    }
    config = tmp / "desired.json"
    config.write_text(json.dumps(desired))
    receipt = tmp / "state" / "svc-lab-state.json"
    ca = tmp / "root.crt"
    ca.write_text("test certificate")
    state_path = tmp / "mock-state.json"
    base_state = {
        "approved": True,
        "advertised": False,
        "resolver": "198.51.100.2",
        "tailvip": "198.51.100.10",
        "node_identity": "node-1",
        "caddy_active": True,
        "caddy_healthy": True,
        "dns_active": True,
        "live_config": {},
    }
    drain_marker = tmp / "state" / "svc-lab-drained"
    lock_file = tmp / "state" / "operation.lock"
    env = os.environ | {
        "MOCK_STATE": str(state_path),
        "SVC_LAB_TAILSCALE": str(bin_dir / "tailscale"),
        "SVC_LAB_SYSTEMCTL": str(bin_dir / "systemctl"),
        "SVC_LAB_CURL": str(bin_dir / "curl"),
        "SVC_LAB_EXPECTED_UID": str(os.getuid()),
        "SVC_LAB_EXPECTED_GID": str(os.getgid()),
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    common = [
        sys.executable, str(controller),
        "--config", str(config), "--receipt", str(receipt),
        "--drain-marker", str(drain_marker), "--lock-file", str(lock_file),
        "--ca-certificate", str(ca), "--approval-timeout", "0", "--poll-interval", "0", "--json",
    ]

    def invoke(command, succeeds=True, extra=()):
        result = subprocess.run([*common, command, *extra], env=env, text=True, capture_output=True)
        assert (result.returncode == 0) is succeeds, (command, result.stdout, result.stderr)
        return json.loads(result.stdout)

    def reset(**changes):
        write_json(state_path, base_state | changes)
        receipt.unlink(missing_ok=True)
        drain_marker.unlink(missing_ok=True)

    # Fresh apply creates the live config and a derived private receipt.
    reset()
    assert invoke("apply")["state"] == "converged"
    first_receipt = json.loads(receipt.read_text())
    assert first_receipt["resolverAddress"] == "198.51.100.2"
    assert first_receipt["address"] == "198.51.100.10"
    assert "preparedState" not in first_receipt
    status = invoke("status")
    assert status["state"] == "converged"
    assert "198.51.100." not in json.dumps(status)
    calls = json.loads(state_path.read_text())["calls"]
    assert any(call[:3] == ["systemctl", "restart", "--no-block"] for call in calls)

    # Reapplying an already converged service is idempotent.
    assert invoke("apply")["state"] == "converged"
    state = json.loads(state_path.read_text())
    assert state["live_config"] == desired
    assert state["advertised"] is True

    # Readdressing and TailVIP rotation replace the receipt atomically.
    original_inode = receipt.stat().st_ino
    state |= {"resolver": "198.51.100.9", "tailvip": "198.51.100.99"}
    write_json(state_path, state)
    assert invoke("apply")["state"] == "converged"
    rotated = json.loads(receipt.read_text())
    assert (rotated["resolverAddress"], rotated["address"]) == ("198.51.100.9", "198.51.100.99")
    assert receipt.stat().st_ino != original_inode

    # Pending approval never leaves DNS authorized.
    reset(approved=False)
    assert invoke("apply", succeeds=False)["state"] == "failed"
    assert not receipt.exists()
    assert json.loads(state_path.read_text())["dns_active"] is False

    # Drift and malformed live config are reported without mutation.
    reset(advertised=True, live_config={"version": "0.0.1", "services": {}})
    assert invoke("status", succeeds=False)["state"] == "drifted"

    # Unsafe receipt permissions and symlinks are rejected.
    reset(advertised=True, live_config=desired)
    assert invoke("apply")["state"] == "converged"
    receipt.chmod(0o644)
    assert invoke("status", succeeds=False)["state"] == "drifted"
    receipt.unlink()
    receipt.symlink_to(config)
    assert invoke("status", succeeds=False)["state"] == "drifted"
    reset(advertised=True, live_config="malformed")
    assert invoke("status", succeeds=False)["state"] == "drifted"

    # A receipt for a different desired configuration is rejected.
    reset(advertised=True, live_config=desired)
    assert invoke("apply")["state"] == "converged"
    wrong_digest = json.loads(receipt.read_text())
    wrong_digest["desiredConfigSha256"] = "0" * 64
    write_json(receipt, wrong_digest)
    assert invoke("status", succeeds=False)["state"] == "drifted"

    # An expired receipt fails status even when live state is otherwise valid.
    reset(advertised=True, live_config=desired)
    assert invoke("apply")["state"] == "converged"
    expired = json.loads(receipt.read_text())
    expired["expiresAt"] = int(time.time()) - 1
    write_json(receipt, expired)
    assert invoke("status", succeeds=False)["state"] == "drifted"

    # Caddy and CLI failures fail closed.
    reset(caddy_active=False)
    assert invoke("apply", succeeds=False)["message"] == "Caddy service is inactive"
    assert not receipt.exists()
    reset(gateway_http_status="400")
    probe = invoke("status", succeeds=False)
    assert probe["state"] == "gateway-unhealthy"
    assert probe["message"] == "HTTPS gateway health probe returned HTTP 400"

    # A CLI JSON schema mismatch fails closed.
    reset(backend="Unexpected")
    assert invoke("apply", succeeds=False)["state"] == "failed"
    reset(status_value=[])
    assert invoke("apply", succeeds=False)["state"] == "failed"
    reset(fail_cli="tailscale")
    assert invoke("apply", succeeds=False)["state"] == "failed"
    assert not receipt.exists()
    calls = json.loads(state_path.read_text())["calls"]
    assert ["systemctl", "stop", "--no-block", "tailscaled.service"] in calls

    # Post-apply live-config drift is rejected.
    reset(drift_after_apply=True)
    assert invoke("apply", succeeds=False)["state"] == "failed"
    assert not receipt.exists()
    assert json.loads(state_path.read_text())["advertised"] is False

    # A protected-state replacement failure after advertisement fails closed.
    reset()
    receipt.mkdir(parents=True)
    assert invoke("apply", succeeds=False)["state"] == "failed"
    failed_state = json.loads(state_path.read_text())
    assert failed_state["advertised"] is False
    assert failed_state["dns_active"] is False
    receipt.rmdir()

    # Drain is explicit, preserves desired config, and is idempotent.
    reset()
    assert invoke("apply")["state"] == "converged"
    assert invoke("drain")["state"] == "drained"
    drained = json.loads(state_path.read_text())
    assert drained["live_config"] == desired
    assert drained["dns_active"] is False
    assert not receipt.exists()
    assert drain_marker.exists()
    assert invoke("reconcile")["state"] == "drained"
    assert json.loads(state_path.read_text())["advertised"] is False
    # Reconciliation reasserts withdrawal if live state is changed externally.
    state = json.loads(state_path.read_text())
    state["advertised"] = True
    write_json(state_path, state)
    assert invoke("reconcile")["state"] == "drained"
    assert json.loads(state_path.read_text())["advertised"] is False
    assert invoke("status", succeeds=False)["state"] == "drained"
    assert invoke("drain")["state"] == "drained"

    # Even a partial drain failure records intent before touching live state.
    assert invoke("apply")["state"] == "converged"
    state = json.loads(state_path.read_text())
    state["fail_cli"] = "tailscale"
    write_json(state_path, state)
    assert invoke("drain", succeeds=False)["state"] == "failed"
    assert drain_marker.exists()
    state["fail_cli"] = None
    write_json(state_path, state)
    assert invoke("reconcile")["state"] == "drained"

    # Explicit apply clears the marker and restores the declarative service.
    assert invoke("apply")["state"] == "converged"
    assert not drain_marker.exists()

    # Concurrent reconciles serialize and leave one valid receipt.
    reset(delay=0.1)
    processes = [subprocess.Popen([*common, "reconcile"], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
    for process in processes:
        stdout, stderr = process.communicate(timeout=10)
        assert process.returncode == 0, (stdout, stderr)
    assert json.loads(receipt.read_text())["service"] == "svc:lab"
