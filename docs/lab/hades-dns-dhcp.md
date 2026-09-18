# Hades LAN DNS and DHCP

Hades is the declarative LAN DNS server at `192.168.17.2`. Its dnsmasq listener
is restricted to `enp1s0`; the separate tailnet CoreDNS listener remains
restricted to `tailscale0`.

LAN DNS publishes only canonical machine records in
`lab.xavierchanth.xyz`. The zone is authoritative-negative for gateway service
names, so LAN clients never receive a TailVIP or a direct Caddy address. Public
records outside that private machine zone are resolved through the configured
public forwarders. The tailnet resolver independently publishes the explicit
gateway names backed by `svc:lab`.

## Private reservation overlay

The repository stores logical reservation intent only. Hardware bindings live
on Hades at:

```text
/var/lib/lab-dns-dhcp/private-reservations.json
```

The file must be owned by `root:root`, mode `0600`, and contain every declared
reservation exactly once:

```json
{
  "version": 1,
  "bindings": {
    "hades": { "macAddress": "<local value>" },
    "poseidon": { "macAddress": "<local value>" },
    "zeus": { "macAddress": "<local value>" },
    "eris": { "macAddress": "<local value>" }
  }
}
```

The renderer reads this file only at service start and writes the complete
dnsmasq configuration to `/run/lab-dns-dhcp/dnsmasq.conf` with mode `0600`.
The overlay and generated reservation bindings never enter the Nix store or
public migration reports. Missing, partial, duplicated, or insecure overlay
state prevents DHCP configuration from being rendered.

## DHCP authority interlock

LAN DNS starts without DHCP. The attended cutover tool arms Hades with a
prepared-state identifier:

```console
sudo lab-dhcp-authority arm
```

`arm` consumes the root-owned, mode-`0600`
`/var/lib/lab-dns-dhcp/phase2-prepared-receipt.json`. The receipt must identify
Phase 2, prove Charon DHCP silence, name the prepared state, match the private
overlay SHA-256 and current Hades boot identity, identify the
`charon-to-hades` transition, and remain unexpired. Provisional authority has a
hard deadline of at most four minutes and no later than the source receipt.
Hades schedules a transaction-bound forced-expiry action 45 seconds before
that deadline. The margin covers bounded cancellation, lifecycle and render
lock waits plus the aggregate bounded stop/show/KILL fence path. This is a
local safety bound under an operating system that continues scheduling systemd;
the attended cutover still requires live responder probes rather than treating
the timer as cross-host proof. After the
cutover proves that Hades is the sole DHCP responder, confirm the same state:

```console
sudo lab-dhcp-authority confirm <prepared-state-id>
```

Confirmation revalidates the protected source receipt, overlay digest,
prepared state, transition, Charon-silent proof, and boot identity under the
same lifecycle lock used by the watchdog. Its replacement is written to a
private temporary file, flushed, atomically renamed, and followed by a
directory flush. The watchdog repeats the complete validation every 30 seconds.
Missing, malformed, expired, drifted, or reboot-stale state stops dnsmasq,
revokes the authority file, and starts a DNS-only configuration. A confirmed
authority remains bounded by the source receipt and current boot; renewal or a
later durable finalization is part of the still-locked coordinated cutover.
The recorded `active` operation outcome is historical evidence of a completed
transition, not a permanent liveness promise: a later cancellation tombstone
is authoritative and prevents that transaction from starting DHCP again.

Emergency rollback first stops Hades DHCP:

```console
sudo lab-dhcp-authority disarm
```

Only after a broadcast probe proves Hades silent may Charon DHCP start. This
ordering is a required contract for the future attended mutation adapter; that
adapter remains locked. The Hades interlock provides the local fail-closed half
of the contract.

The final pool is `192.168.17.100` through `192.168.17.199`. Infrastructure
and reservations occupy `.1` through `.99`. Clients receive Charon `.17.1` as
router, Hades `.17.2` as DNS, `lab.xavierchanth.xyz` and `lan` as search
domains, and twelve-hour leases after the migration soak.
