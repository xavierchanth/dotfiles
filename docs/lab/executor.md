# Executor

Executor is the Lab's MCP gateway and capability manager. The pinned
`v1.6.8` container runs on Hades and stores its complete durable state under
`/var/lib/executor`.

## Service boundary

- Executor listens on plain HTTP at `127.0.0.1:4788` only.
- The [service gateway](service-gateway.md) owns private DNS, TLS,
  tailnet-only ingress, proxy health, streaming behavior, and rollback for
  `https://executor.lab.xavierchanth.xyz`.
- Caddy proxies the stable service surface to the loopback listener and
  preserves authentication and streaming headers.
- Executor owns MCP registration, credentials, tool policy, and capability
  lifecycle. Cage and future services remain behind Executor rather
  than becoming direct agent dependencies.
- Local-network access and stdio MCP launch are disabled until their adapter
  gates below are satisfied.

The local readiness endpoint is `GET /api/health`; a healthy instance returns
HTTP 200 with `{"status":"ok"}`. The agent-facing Streamable HTTP endpoint is
`/mcp`.

## First run

After the configuration is deployed, verify `executor.service` and browse to
the private HTTPS hostname from a tailnet client. The first account created in
the setup screen becomes the owner. Complete this enrollment before creating
invite links or registering integrations.

Keep service credentials in Executor's encrypted provider configuration. Do
not place adapter tokens in the declarative container or Caddy configuration.

## Backups and restore

`executor-backup.timer` runs daily. It stops the Podman-managed Executor container, archives
the complete `/var/lib/executor` tree with numeric ownership, writes a manifest
containing the pinned release and inspected OCI image digest plus checksums,
then restarts the container. Backup directories
live under `/var/backups/executor` and are retained for 14 days. This local
snapshot and the manual restore procedure below are sufficient for the
experimental, rebuildable pilot; loss of Hades may also lose these snapshots.

Off-host restic backup is optional hardening for a later durable service. To
enable it, set `dotfiles.executor.offsiteBackup.enable = true` and provision
these root-readable runtime files on Hades outside the Nix store:

- `/run/keys/executor-restic-repository`: the real off-host restic repository
  URI, such as an SFTP repository on the NAS.
- `/run/keys/executor-restic-password`: the repository password.
- `/run/keys/executor-restic-expected-repository-id`: the immutable repository
  ID returned by `restic cat config` after the intended repository is created.

Nix passes them to the optional units with systemd credentials. When enabled,
`executor-backup-preflight.service` accepts only an off-host restic transport,
rejects loopback destinations, and compares the live repository ID with the
pinned credential. Missing files, an uninitialized repository, an identity
mismatch, or an unreachable destination then prevent Executor from starting.
The endpoint, password, and expected ID must not be encoded in Git or the Nix
store. Their paths can be changed through
`dotfiles.executor.offsiteBackup` options.

To restore:

1. Stop `executor.service`.
2. Move the existing `/var/lib/executor` aside so rollback remains possible.
3. Extract `executor-state.tar.gz` from the selected backup at `/var/lib` as
   root, preserving numeric ownership.
4. Confirm `/var/lib/executor/data` is owned by `65532:65532`.
5. Start `executor.service` and verify `/api/health`, owner login, integrations,
   policies, and MCP discovery through the private hostname.

When off-host backup is enabled, `executor-restore-check.service` performs a
clean remote restore validation without altering live state.

## Upgrade and rollback

Change both the release tag and the architecture-specific image digest in the
Executor NixOS module. Build the Hades configuration without activation, take
an on-demand `executor-backup.service` backup, deploy, and verify health plus a
read-only MCP call.

For rollback, restore the previous NixOS generation. If the new release
migrated durable state incompatibly, also restore the pre-upgrade backup before
starting the previous image. The manifest identifies the exact image used for
each backup.

## Adapter gates

Each adapter starts deny-by-default and requires all of the following before it
is made available to an agent:

1. A named owner and a documented, version-pinned product contract.
2. Credentials injected into Executor without raw-token exposure to clients.
3. An explicit tool allowlist, destructive-operation approval rules, and a
   blocked-operation test.
4. A harmless read-only end-to-end call through the stable `/mcp` endpoint.
5. Audit evidence that the client receives only the intended scoped tools.

Cage and JIO remain independently owned products; required product changes
return to their teams. Enabling local-network targets or per-task stdio MCP
processes is a separate reviewed change after isolation and lifecycle behavior
are proven.
