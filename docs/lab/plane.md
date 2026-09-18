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

The proxy publishes only HTTP on loopback. Gateway Caddy owns the external
listener, TLS, forwarded headers, WebSocket forwarding, and Tailscale exposure.
Plane's own pinned proxy owns its 10 MiB request-body limit. Plane's web URL and
allowed CORS origin are both the public HTTPS origin.

Plane replaces the proxy image's bundled ACME-aware Caddyfile with a
Nix-generated HTTP-only configuration. Automatic HTTPS is disabled and the
container listens only on `:80`; empty upstream `CERT_*` values therefore cannot
prevent the loopback proxy from starting. The generated Caddyfile is syntax
validated during the Nix build.

## Gateway handoff

Plane presents one complete HTTP origin to Gateway:

| Contract | Value |
| --- | --- |
| Upstream | `http://127.0.0.1:8080` |
| Health path | `/` |
| Healthy response | HTTP `200` |
| Public origin and `Host` | `https://plane.lab.xavierchanth.xyz` |
| CORS origin | `https://plane.lab.xavierchanth.xyz` |
| Request-body limit | 10 MiB (`10485760` bytes), enforced by Plane |

The pinned Plane proxy owns all application routing: `/api/*`, `/auth/*`,
`/static/*`, `/uploads/*`, `/live/*`, `/spaces/*`, `/god-mode/*`, and the web
frontend fallback. `/live/*` carries the live service's upgraded connections;
both Plane's proxy and Gateway must preserve normal WebSocket upgrade behavior.
Gateway must proxy the origin without path rewriting, a second body-size limit,
or a second authentication layer.

The limit applies to the complete HTTP request body, so a multipart attachment
must be slightly smaller than 10 MiB after encoding overhead. Gateway should not
advertise a larger supported upload size.

Gateway Deploy has accepted this handoff and owns the corresponding route.

## Runtime topology

The pinned Community release uses one replica of each supported service:

- `web`, `space`, and `admin` provide the user, spaces, and instance-admin
  frontends;
- `api`, `worker`, `beat-worker`, and the one-shot `migrator` provide the
  application API, asynchronous work, scheduled work, and schema migrations;
- `live` provides real-time updates under `/live/*`;
- `plane-db`, `plane-redis`, `plane-mq`, and `plane-minio` provide PostgreSQL,
  Valkey, RabbitMQ, and S3-compatible uploads;
- `proxy` presents the single loopback origin consumed by Gateway.

PostgreSQL alone is insufficient for this release. Valkey, RabbitMQ, and object
storage are runtime dependencies of the supported Plane stack. The pilot uses
the bundled single-instance dependencies rather than external or replicated
services.

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
starts the stack, and gives the loopback endpoint a bounded readiness window of
about two minutes after Compose returns. The wider systemd start timeout leaves
room for first-run image pulls. It starts after Docker and network readiness and
is a required lab rollout unit. A failed health check prints the Compose state
and recent proxy logs, then fails the rollout.

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
- the exact compose and HTTP-only Caddy definitions, image inventory, and Plane
  release identifier;
- SHA-256 checksums for every snapshot artifact.

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
2. Stop `plane.service` and prepare empty `plane_pgdata` and `plane_uploads`
   volumes. Recovery replaces those volumes; never unpack a snapshot over a
   running instance.
3. Restore the snapshot's `plane.env` to `/var/lib/plane/plane.env` with root
   ownership and mode `0600`. When rebuilding without preserving pilot data,
   allow Plane to generate new credentials instead.
4. Install the snapshot's matching pinned Nix generation and start only
   `plane-db`. Import `postgres.sql.gz` into its initially empty `plane`
   database with `psql` and `ON_ERROR_STOP` enabled.
5. Extract `uploads.tar.gz` into the empty `plane_uploads` volume, preserving
   its archive-relative paths.
6. Start the complete Plane stack and verify login, basic work-item/comment
   operations, one attachment, and restart persistence.

Before changing the Plane release pin, run `plane-backup.service` and retain its
completed snapshot. A NixOS rollback restores the earlier application images
and definition, but it cannot reverse a database migration. If the older release
cannot use the migrated database, restore the matching pre-upgrade PostgreSQL
dump, uploads archive, and `plane.env` before starting it.

Executor integration is a separate validation step when Agent Tools enables the
connector; it does not block the initial human-only Plane pilot.
