#!/usr/bin/env python3
"""Reconcile one Tailscale Service host from a declarative serve config."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from typing import Any


class GatewayError(RuntimeError):
    pass


def command(name: str) -> str:
    return os.environ.get(f"SVC_LAB_{name.upper()}", name.lower())


def run(argv: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(argv, text=True, capture_output=True, check=False)
    if check and result.returncode != 0:
        detail = " ".join(result.stderr.strip().split())[:240]
        raise GatewayError(f"{Path(argv[0]).name} failed" + (f": {detail}" if detail else ""))
    return result


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise GatewayError(f"invalid JSON at {path}") from error


def desired_config(path: Path, service: str, target: str) -> dict[str, Any]:
    value = load_json(path)
    expected = {"version": "0.0.1", "services": {service: {"advertised": True, "endpoints": {"tcp:443": target}}}}
    if value != expected:
        raise GatewayError("desired Service config violates the svc:lab contract")
    return value


def live_config() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="svc-lab-live.") as directory:
        destination = Path(directory) / "config.json"
        run([command("tailscale"), "serve", "get-config", "--all", str(destination)])
        return load_json(destination)


def tailscale_status() -> dict[str, Any]:
    result = run([command("tailscale"), "status", "--json"])
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise GatewayError("tailscale status returned invalid JSON") from error
    if not isinstance(value, dict) or value.get("BackendState") != "Running" or not isinstance(value.get("Self"), dict):
        raise GatewayError("tailscaled is not authenticated and running")
    return value


def contains_service(value: Any, service: str) -> bool:
    if value == service:
        return True
    if isinstance(value, dict):
        return service in value or any(contains_service(item, service) for item in value.values())
    if isinstance(value, list):
        return any(contains_service(item, service) for item in value)
    return False


def live_addresses(status: dict[str, Any], service: str) -> tuple[str, str | None, str, bool]:
    self_status = status["Self"]
    addresses = self_status.get("TailscaleIPs", [])
    resolver = next((address for address in addresses if ipaddress.ip_address(address).version == 4), None)
    if resolver is None:
        raise GatewayError("tailscale status has no node IPv4 address")
    node_identity = self_status.get("ID") or self_status.get("PublicKey")
    if not isinstance(node_identity, str) or not node_identity:
        raise GatewayError("tailscale status has no stable node identity")
    advertised = contains_service(self_status.get("CapMap", {}).get("service-host", []), service)
    node_networks = {ipaddress.ip_network(f"{address}/32", strict=False) for address in addresses if ipaddress.ip_address(address).version == 4}
    candidates: list[str] = []
    for raw_prefix in self_status.get("PrimaryRoutes", []):
        try:
            prefix = ipaddress.ip_network(raw_prefix, strict=False)
        except ValueError:
            continue
        if prefix.version == 4 and prefix.prefixlen == 32 and prefix not in node_networks:
            candidates.append(str(prefix.network_address))
    tailvip = candidates[0] if len(candidates) == 1 else None
    return resolver, tailvip, node_identity, advertised


def config_sha256(config: dict[str, Any]) -> str:
    encoded = json.dumps(config, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def gateway_health_error(args: argparse.Namespace) -> str | None:
    if run([command("systemctl"), "is-active", "--quiet", "caddy.service"], check=False).returncode != 0:
        return "Caddy service is inactive"
    url = f"https://{args.health_host}:{args.port}{args.health_path}"
    result = run([
        command("curl"), "--silent", "--show-error", "--max-time", "5",
        "--output", "/dev/null", "--write-out", "%{http_code}",
        "--cacert", args.ca_certificate, "--resolve", f"{args.health_host}:{args.port}:{args.bind_address}", url,
    ], check=False)
    if result.returncode != 0:
        return "HTTPS gateway health probe failed"
    status = result.stdout.strip()
    if not status.isdigit() or not 200 <= int(status) < 300:
        return f"HTTPS gateway health probe returned HTTP {status or 'unknown'}"
    return None


def read_receipt(path: Path) -> dict[str, Any] | None:
    try:
        stat = path.lstat()
        expected_uid = int(os.environ.get("SVC_LAB_EXPECTED_UID", "0"))
        expected_gid = int(os.environ.get("SVC_LAB_EXPECTED_GID", "0"))
        if path.is_symlink() or stat.st_uid != expected_uid or stat.st_gid != expected_gid or stat.st_mode & 0o777 != 0o600:
            return None
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else None
    except (OSError, json.JSONDecodeError):
        return None


def marker_present(path: Path) -> bool:
    try:
        stat = path.lstat()
        expected_uid = int(os.environ.get("SVC_LAB_EXPECTED_UID", "0"))
        expected_gid = int(os.environ.get("SVC_LAB_EXPECTED_GID", "0"))
        return not path.is_symlink() and stat.st_uid == expected_uid and stat.st_gid == expected_gid and stat.st_mode & 0o777 == 0o600
    except OSError:
        return False


def write_marker(path: Path) -> None:
    write_receipt(path, {"version": 1, "state": "drained"})


@contextmanager
def mutation_lock(path: Path):
    ensure_private_directory(path.parent)
    flags = os.O_CREAT | os.O_RDWR
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        stat = os.fstat(descriptor)
        expected_uid, expected_gid = expected_owner()
        if stat.st_uid != expected_uid or stat.st_gid != expected_gid:
            raise GatewayError(f"unsafe lock ownership at {path}")
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)


def receipt_matches(path: Path, *, service: str, resolver: str, tailvip: str, node_identity: str, digest: str) -> bool:
    value = read_receipt(path)
    return value is not None and value == {
        "version": 1,
        "service": service,
        "resolverAddress": resolver,
        "address": tailvip,
        "nodeIdentity": node_identity,
        "desiredConfigSha256": digest,
        "expiresAt": value.get("expiresAt"),
    } and isinstance(value.get("expiresAt"), int) and value["expiresAt"] > int(time.time())


def expected_owner() -> tuple[int, int]:
    return int(os.environ.get("SVC_LAB_EXPECTED_UID", "0")), int(os.environ.get("SVC_LAB_EXPECTED_GID", "0"))


def ensure_private_directory(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    stat = path.lstat()
    expected_uid, expected_gid = expected_owner()
    if path.is_symlink() or stat.st_uid != expected_uid or stat.st_gid != expected_gid:
        raise GatewayError(f"unsafe protected-state directory at {path}")
    os.chmod(path, 0o700)


def write_receipt(path: Path, value: dict[str, Any]) -> None:
    ensure_private_directory(path.parent)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(value, stream, sort_keys=True, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def fail_closed(receipt: Path) -> None:
    try:
        try:
            receipt.unlink(missing_ok=True)
            if receipt.parent.exists():
                fsync_directory(receipt.parent)
        except OSError:
            pass
    finally:
        run([command("systemctl"), "stop", "tailnet-gateway-dns.service"], check=False)


def withdraw_and_verify(args: argparse.Namespace) -> None:
    run([command("tailscale"), "serve", "drain", args.service])
    deadline = time.monotonic() + args.approval_timeout
    while True:
        status = tailscale_status()
        _, tailvip, _, advertised = live_addresses(status, args.service)
        if not advertised and tailvip is None:
            return
        if time.monotonic() >= deadline:
            raise GatewayError("svc:lab did not drain before the timeout")
        time.sleep(args.poll_interval)


def fail_closed_dataplane(args: argparse.Namespace) -> None:
    try:
        withdraw_and_verify(args)
    except (GatewayError, OSError):
        # If the Service cannot be proven withdrawn, stop the overlay dataplane.
        run([command("systemctl"), "stop", "--no-block", "tailscaled.service"], check=False)


def reconcile_drain(args: argparse.Namespace) -> None:
    withdraw_and_verify(args)


def inspect(args: argparse.Namespace, *, require_dns: bool) -> tuple[str, str, dict[str, Any]]:
    desired = desired_config(Path(args.config), args.service, args.target)
    drained = marker_present(Path(args.drain_marker))
    gateway_error = gateway_health_error(args)
    if gateway_error is not None:
        return "gateway-unhealthy", gateway_error, {}
    try:
        status = tailscale_status()
        current = live_config()
        resolver, tailvip, node_identity, advertised = live_addresses(status, args.service)
    except GatewayError as error:
        return "failed", str(error), {}
    if current != desired:
        return "drifted", "live Service config differs from the declarative config", {}
    if not advertised:
        if drained and tailvip is None:
            return "drained", "svc:lab is intentionally drained", {}
        return "unadvertised", "svc:lab is configured but not advertised", {}
    if drained:
        return "drifted", "svc:lab is advertised while the drain marker is present", {}
    if tailvip is None:
        return "pending-approval", "svc:lab is advertised without one approved TailVIP route", {}
    digest = config_sha256(desired)
    if not receipt_matches(Path(args.receipt), service=args.service, resolver=resolver, tailvip=tailvip, node_identity=node_identity, digest=digest):
        return "drifted", "runtime receipt is missing, expired, or differs from live state", {}
    if require_dns and run([command("systemctl"), "is-active", "--quiet", "tailnet-gateway-dns.service"], check=False).returncode != 0:
        return "failed", "tailnet gateway DNS is inactive", {}
    return "converged", "svc:lab is configured, approved, advertised, and serving private DNS", {}


def emit(state: str, message: str, details: dict[str, Any], json_mode: bool) -> None:
    if json_mode:
        print(json.dumps({"state": state, "message": message, **details}, sort_keys=True))
    else:
        print(f"{state}: {message}")


def apply_locked(args: argparse.Namespace, *, clear_marker: bool) -> int:
    receipt = Path(args.receipt)
    try:
        if clear_marker:
            marker = Path(args.drain_marker)
            marker.unlink(missing_ok=True)
            if marker.parent.exists():
                fsync_directory(marker.parent)
        desired = desired_config(Path(args.config), args.service, args.target)
        gateway_error = gateway_health_error(args)
        if gateway_error is not None:
            raise GatewayError(gateway_error)
        tailscale_status()
        run([command("tailscale"), "serve", "set-config", "--all", args.config])
        run([command("tailscale"), "serve", "advertise", args.service])
        deadline = time.monotonic() + args.approval_timeout
        while True:
            status = tailscale_status()
            resolver, tailvip, node_identity, advertised = live_addresses(status, args.service)
            if advertised and tailvip is not None:
                break
            if time.monotonic() >= deadline:
                raise GatewayError("svc:lab is pending approval or has no active TailVIP route")
            time.sleep(args.poll_interval)
        if live_config() != desired:
            raise GatewayError("live Service config differs after reconciliation")
        write_receipt(receipt, {
            "version": 1,
            "service": args.service,
            "resolverAddress": resolver,
            "address": tailvip,
            "nodeIdentity": node_identity,
            "desiredConfigSha256": config_sha256(desired),
            "expiresAt": int(time.time()) + args.receipt_ttl,
        })
        run([command("systemctl"), "restart", "--no-block", "tailnet-gateway-dns.service"], check=False)
        state, message, details = inspect(args, require_dns=False)
        if state != "converged":
            raise GatewayError(message)
        emit(state, message, details, args.json)
        return 0
    except (GatewayError, OSError) as error:
        fail_closed_dataplane(args)
        fail_closed(receipt)
        emit("failed", str(error), {}, args.json)
        return 1


def apply(args: argparse.Namespace) -> int:
    with mutation_lock(Path(args.lock_file)):
        return apply_locked(args, clear_marker=True)


def reconcile(args: argparse.Namespace) -> int:
    with mutation_lock(Path(args.lock_file)):
        if marker_present(Path(args.drain_marker)):
            try:
                reconcile_drain(args)
                fail_closed(Path(args.receipt))
                emit("drained", "svc:lab remains intentionally drained", {}, args.json)
                return 0
            except (GatewayError, OSError) as error:
                fail_closed_dataplane(args)
                fail_closed(Path(args.receipt))
                emit("failed", str(error), {}, args.json)
                return 1
        return apply_locked(args, clear_marker=False)


def status_command(args: argparse.Namespace) -> int:
    state, message, details = inspect(args, require_dns=not args.without_dns)
    emit(state, message, details, args.json)
    return 0 if state == "converged" else 1


def drain(args: argparse.Namespace) -> int:
    receipt = Path(args.receipt)
    with mutation_lock(Path(args.lock_file)):
      try:
        # Persist operator intent before touching live state so a partial drain
        # cannot be undone by the periodic reconciler.
        write_marker(Path(args.drain_marker))
        reconcile_drain(args)
        fail_closed(receipt)
        emit("drained", "svc:lab is withdrawn and private DNS is stopped", {}, args.json)
        return 0
      except (GatewayError, OSError) as error:
        fail_closed_dataplane(args)
        fail_closed(receipt)
        emit("failed", str(error), {}, args.json)
        return 1


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("command", choices=["apply", "reconcile", "status", "drain"])
    result.add_argument("--service", default="svc:lab")
    result.add_argument("--config", required=True)
    result.add_argument("--receipt", required=True)
    result.add_argument("--drain-marker", required=True)
    result.add_argument("--lock-file", required=True)
    result.add_argument("--target", default="tcp://127.0.0.1:8443")
    result.add_argument("--bind-address", default="127.0.0.1")
    result.add_argument("--port", type=int, default=8443)
    result.add_argument("--health-host", default="lab.xavierchanth.xyz")
    result.add_argument("--health-path", default="/api/healthcheck")
    result.add_argument("--ca-certificate", required=True)
    result.add_argument("--approval-timeout", type=float, default=60)
    result.add_argument("--poll-interval", type=float, default=2)
    result.add_argument("--receipt-ttl", type=int, default=600)
    result.add_argument("--without-dns", action="store_true")
    result.add_argument("--json", action="store_true")
    return result


def main() -> int:
    args = parser().parse_args()
    if args.command == "apply":
        return apply(args)
    if args.command == "reconcile":
        return reconcile(args)
    if args.command == "status":
        return status_command(args)
    return drain(args)


if __name__ == "__main__":
    sys.exit(main())
