# Lab network cutover

This runbook defines the two-phase move to the `192.168.17.0/24` LAN. Charon remains the minimal router, NAT, firewall, Wi-Fi, and recovery boundary. Hades becomes the final DHCP/DNS and tailnet gateway. IPv6 forwarding and router advertisements remain disabled in phase 1.

The packaged operator interface is:

```console
nix run .#lab-network-cutover -- phase1 prepare
nix run .#lab-network-cutover -- phase1 apply
nix run .#lab-network-cutover -- phase1 status
nix run .#lab-network-cutover -- phase1 confirm
nix run .#lab-network-cutover -- phase1 rollback
```

Replace `phase1` with `phase2` for the DHCP-authority handoff.

## Current safety lock

`prepare` and `status` are implemented and read-only. `apply`, `confirm`, and `rollback` intentionally refuse to run until a real Charon capture has established the interface/bridge topology and a separately tested mutation adapter provides all of these controls:

- complete on-device backups with checksums;
- reboot-persistent, 15-minute commit-confirm watchdogs armed before mutation;
- automatic wired and Wi-Fi lease renewal;
- live DHCP authority probes and cold-boot/boot-order tests;
- an effective DHCP fence, including same-bridge broadcasts;
- phase-2 fallback that enables Charon only after Hades is proven silent; ambiguity fails closed.

This lock is part of the design. It prevents a generic or guessed OpenWrt configuration from being treated as deployable.

## Private device mapping

The repository contains only opaque reservation references. Create the runtime mapping at:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/lab-network-cutover/devices.json
```

It must be a regular, non-symlink file owned by the operator with mode `0600`:

```json
{
  "schemaVersion": 1,
  "reservations": {
    "hades-lan": { "mac": "<local value>" },
    "poseidon-lan": { "mac": "<local value>" },
    "zeus-lan": { "mac": "<local value>" },
    "eris-lan": { "mac": "<local value>" }
  }
}
```

MAC addresses are validated locally. Receipts contain only the mapping digest, never its contents. Runs and receipts live below `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/lab-network-cutover` with private permissions.

## Phase boundaries

Phase 1 changes addressing while Charon remains the only DHCP authority. Managed infrastructure is dual-addressed during recovery, Charon retains the temporary legacy recovery address, transition leases are five minutes, and the process waits one complete previous maximum lease lifetime before relying on the new subnet.

Phase 2 starts only after phase 1 is confirmed and soaked. Hades begins inhibited. Charon DHCP is stopped and proven silent before Hades starts. The rollback pair must disable Hades first and probe that it is silent before Charon can resume; if the proof fails, DHCP stays off for attended recovery.

Every `apply` must compare the immutable prepare receipt with the current manifest, local mapping digest, topology evidence, backup checksums, lease timing, and expected service fingerprints. Any owned drift requires an explicit new prepare/import/overwrite decision; it is never merged automatically.

## Required validation gates

Before removing the safety lock, exercise backups and restore, persistent watchdogs, exactly-one-DHCP probes, automatic client renewal, wired and Wi-Fi clients, cold reboot and boot order, Hades-down behavior, recovery without manual client configuration, and privacy scans. Firewall tests must use distinct Lab, upstream-LAN, and internet endpoints plus nftables counters. In particular, Lab traffic must not reach the captured directly connected upstream prefix or gateway UI, while established internet replies and Charon's own narrowly required upstream traffic remain functional.
