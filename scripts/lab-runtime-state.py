#!/usr/bin/env python3
import argparse
import hashlib
import ipaddress
import json
import os
import re
import stat
import sys
import tempfile


def private_json(path, expected_uid, expected_gid):
    info = os.lstat(path)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ValueError("state must be a regular non-symlink file")
    if (info.st_uid != expected_uid or info.st_gid != expected_gid
            or stat.S_IMODE(info.st_mode) != 0o600):
        raise ValueError(f"state ownership or mode is unsafe: {path}")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def validate_tailnet(args):
    state = private_json(args.state, args.expected_uid, args.expected_gid)
    required = {"version", "service", "resolverAddress", "address", "expiresAt", "preparedState"}
    if set(state) != required or state["version"] != 1 or state["service"] != "svc:lab":
        raise ValueError("invalid svc:lab state schema")
    if not isinstance(state["preparedState"], str) or len(state["preparedState"]) < 16:
        raise ValueError("invalid prepared state")
    if not isinstance(state["expiresAt"], int) or state["expiresAt"] <= args.now:
        raise ValueError("expired svc:lab state")
    resolver = ipaddress.IPv4Address(state["resolverAddress"])
    address = ipaddress.IPv4Address(state["address"])
    if resolver == address:
        raise ValueError("resolver and Service destination must differ")
    print(resolver)
    print(address)


def validate_prepared_receipt(receipt, overlay_sha, now, runtime_identity):
    required = {
        "version", "authority", "phase", "transition", "charonDhcpSilent",
        "preparedState", "overlaySha256", "runtimeIdentity", "expiresAt",
    }
    if not (
        set(receipt) == required
        and receipt["version"] == 1
        and receipt["authority"] == "hades"
        and receipt["phase"] == "phase2"
        and receipt["transition"] == "charon-to-hades"
        and receipt["charonDhcpSilent"] is True
        and isinstance(receipt.get("preparedState"), str)
        and len(receipt["preparedState"]) >= 16
        and receipt.get("overlaySha256") == overlay_sha
        and receipt.get("runtimeIdentity") == runtime_identity
        and isinstance(receipt.get("expiresAt"), int)
        and receipt["expiresAt"] > now
    ):
        raise ValueError("invalid phase2 prepared receipt")
    return receipt


def validate_dhcp(args):
    intent = json.load(open(args.intent, encoding="utf-8"))
    overlay = private_json(args.overlay, args.expected_uid, args.expected_gid)
    authority = private_json(args.authority, args.expected_uid, args.expected_gid)
    receipt = private_json(args.receipt, args.expected_uid, args.expected_gid)
    if overlay.get("version") != 1 or set(overlay.get("bindings", {})) != set(intent):
        raise ValueError("reservation bindings do not match logical intent")
    macs = [entry.get("macAddress", "").lower() for entry in overlay["bindings"].values()]
    if len(macs) != len(set(macs)) or not all(re.fullmatch(r"([0-9a-f]{2}:){5}[0-9a-f]{2}", mac) for mac in macs):
        raise ValueError("invalid or duplicate reservation binding")
    overlay_sha = hashlib.sha256(open(args.overlay, "rb").read()).hexdigest()
    receipt = validate_prepared_receipt(receipt, overlay_sha, args.now, args.runtime_identity)
    receipt_sha = hashlib.sha256(open(args.receipt, "rb").read()).hexdigest()
    required = {
        "version", "authority", "phase", "transition", "charonDhcpSilent",
        "preparedState", "overlaySha256", "runtimeIdentity", "sourceReceiptSha256",
        "expiresAt", "activationState", "transactionId", "controllerPid",
    }
    shared = (
        "authority", "phase", "transition", "charonDhcpSilent",
        "preparedState", "overlaySha256", "runtimeIdentity",
    )
    if not (
        set(authority) == required
        and authority["version"] == 1
        and all(authority.get(field) == receipt[field] for field in shared)
        and authority.get("sourceReceiptSha256") == receipt_sha
        and isinstance(authority.get("transactionId"), str)
        and len(authority["transactionId"]) >= 16
        and isinstance(authority.get("controllerPid"), int)
        and authority["controllerPid"] > 0
        and (
            authority.get("activationState") == "active"
            or (
                args.allow_pending
                and authority.get("activationState") == "pending"
                and authority["transactionId"] == args.transaction_id
            )
        )
        and (authority.get("expiresAt") is None or (
            isinstance(authority["expiresAt"], int)
            and args.now < authority["expiresAt"] <= receipt["expiresAt"]
        ))
    ):
        raise ValueError("invalid DHCP authority receipt")
    for name in sorted(intent):
        print(f"dhcp-host={overlay['bindings'][name]['macAddress'].lower()},{intent[name]['address']},{name}")
    return authority


def atomic_write_json(path, value):
    directory = os.path.dirname(path) or "."
    descriptor, temporary = tempfile.mkstemp(prefix=".dhcp-authority.", dir=directory)
    try:
        os.fchmod(descriptor, 0o600)
        os.fchown(descriptor, os.geteuid(), os.getegid())
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(directory, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def confirm_authority(args):
    authority = validate_dhcp(args)
    if not isinstance(authority["expiresAt"], int) or authority["expiresAt"] <= args.now:
        raise ValueError("only current provisional authority can be confirmed")
    if authority["preparedState"] != args.prepared_state:
        raise ValueError("prepared state does not match current authority")
    if not args.transaction_id:
        raise ValueError("confirmation requires a transaction identifier")
    confirmed = authority | {
        "expiresAt": None,
        "activationState": "pending",
        "transactionId": args.transaction_id,
        "controllerPid": args.controller_pid,
    }
    atomic_write_json(args.authority, confirmed)


def activate_authority(args):
    args.allow_pending = True
    authority = validate_dhcp(args)
    if authority["activationState"] != "pending":
        raise ValueError("only pending authority can be activated")
    atomic_write_json(args.authority, authority | {"activationState": "active"})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["tailnet", "dhcp", "confirm", "activate"])
    parser.add_argument("--expected-uid", type=int, default=0)
    parser.add_argument("--expected-gid", type=int, default=0)
    parser.add_argument("--now", type=int, required=True)
    parser.add_argument("--state")
    parser.add_argument("--intent")
    parser.add_argument("--overlay")
    parser.add_argument("--authority")
    parser.add_argument("--receipt")
    parser.add_argument("--prepared-state")
    parser.add_argument("--runtime-identity")
    parser.add_argument("--transaction-id")
    parser.add_argument("--controller-pid", type=int)
    parser.add_argument("--allow-pending", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "tailnet":
            validate_tailnet(args)
        elif args.command == "dhcp":
            validate_dhcp(args)
        elif args.command == "confirm":
            confirm_authority(args)
        else:
            activate_authority(args)
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
