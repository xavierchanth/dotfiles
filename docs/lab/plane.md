# Plane

Plane is the lab's human-visible work ledger. It holds durable projects, work
items, comments, and status; it does not orchestrate agents. Agent automation
reaches Plane through Executor rather than depending on Plane credentials or a
raw Plane address.

## Ownership

- Task and Notes is the accountable Plane application operator. It owns release
  and image pins, upgrades, database migrations, application state layout,
  backup and restore evidence, and Plane application incidents.
- Agent Tools owns only the scoped Plane connector and its capability policy.
  It does not own Plane application state, credentials, upgrades, or recovery.
- Gateway Deploy owns ingress, TLS, and routing between the public service name
  and Plane's loopback listener.
- Lab Deploy owns the Hades host rollout and host-level deployment mechanics.

An incident or change stays with Task and Notes unless evidence places the
failure exclusively in the connector policy, gateway, or host rollout layer.
Handoffs must include the evidence needed by the receiving owner and must not
silently transfer application accountability.

## Deployment contract

- Host: Hades
- Release: Plane CE `v1.3.1`
- Public URL: `https://plane.lab.xavierchanth.xyz`
- Private upstream: `http://127.0.0.1:8080`
- Ingress and TLS owner: the Hades service gateway (Caddy)
- Runtime owner: `plane.service`

The Nix module fetches the exact upstream release compose file by content hash,
applies the repository-owned patch, and rejects any resulting image reference
without an immutable `sha256` manifest digest. Docker Compose is therefore an
implementation detail generated and installed by Nix, not host-edited state.

The proxy publishes only HTTP on loopback. Caddy owns the external listener,
TLS, forwarded headers, WebSockets, Tailscale exposure, and the 10 MiB request
limit. Plane's web URL and allowed CORS origin are both the public HTTPS URL.

## State and secrets

Plane's root-owned deployment state is in `/var/lib/plane`:

- `plane.env`: mode `0600`; database, RabbitMQ, MinIO, application, and live
  service secrets
- `docker-compose.yml`: mode `0444`; the Nix-built deployment definition

The environment file is created once with random credentials when absent. It
must be restored with the application data during disaster recovery; it must
never be committed to the repository or copied into the Nix store.

The stable Compose project name is `plane`. Its persistent Docker volumes are:

- `plane_pgdata`
- `plane_redisdata`
- `plane_uploads`
- `plane_rabbitmq_data`
- `plane_logs_api`
- `plane_logs_worker`
- `plane_logs_beat-worker`
- `plane_logs_migrator`
- `plane_proxy_config`
- `plane_proxy_data`

PostgreSQL and uploads are the authoritative user data. Redis, RabbitMQ,
service logs, and proxy caches/configuration are runtime state and can be
re-created, but remain explicitly named and visible for operations.

## Lifecycle and health

`plane.service` prepares the Nix-owned compose definition and secret file,
starts the stack, and waits up to ten minutes for the loopback HTTP endpoint to
respond successfully. It starts after Docker and network readiness and is a
required lab rollout unit. A failed health check fails the rollout.

Stopping the unit performs a Compose shutdown without deleting persistent
volumes. Rolling back the NixOS generation restores the previous application
definition and image digests; database compatibility must be checked before a
release downgrade.

## Backup and recovery

`plane-backup.timer` creates a root-only local snapshot daily under
`/var/backups/plane/<UTC timestamp>` containing:

- a consistent compressed PostgreSQL logical dump;
- a compressed uploads archive;
- the secret environment file;
- the exact compose definition, image inventory, and Plane release identifier.

Local snapshots are retained for 14 days. For the initial single-user pilot,
manual recovery and manual credential re-entry are acceptable. Hades loss can
therefore lose pilot data, and Plane must be treated as experimental rather
than an authoritative record.

Off-host encrypted backup is optional and disabled by default. It does not
block pilot activation. Before Plane holds unique decisions or important
attachments, manually copy an encrypted snapshot to another machine or storage
provider.

If Plane is promoted to durable or canonical infrastructure, add an off-host
backup contract in Nix. The future seam should support a destination, transport,
least-privilege identity, pinned trust material, credential delivery, and
retention policy without changing the local snapshot format. At that point,
also add disposable restore verification for the latest database dump and
uploads archive.

Pilot recovery is deliberately manual:

1. Rebuild Hades from the pinned Nix configuration.
2. Restore `plane.env` with root ownership and mode `0600`, or accept new
   credentials when rebuilding from scratch.
3. Import the PostgreSQL dump and restore the uploads archive when preserving
   pilot data is worthwhile.
4. Start Plane and verify login, basic work-item/comment operations, one
   attachment, and restart persistence.

Executor integration is a separate validation step when Agent Tools enables the
connector; it does not block the initial human-only Plane pilot.
