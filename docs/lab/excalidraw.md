# Excalidraw

The Lab's persistent diagram workspace is ExcaliDash `v0.6.0`, published only at
`https://excalidraw.lab.xavierchanth.xyz`. It runs as two pinned Podman
containers on Hades: a static frontend and a server-side backend. Caddy owns the
tailnet-only TLS origin and proxies to `127.0.0.1:3100`.

## Product contract

- Frontend unit: `excalidraw.service`
- Backend unit: `excalidraw-backend.service`
- Local frontend: `http://127.0.0.1:3100`
- Backend storage: SQLite at `/var/lib/excalidraw/excalidraw.db`
- Generated JWT and CSRF secrets: `/var/lib/excalidraw/.jwt_secret` and
  `/var/lib/excalidraw/.csrf_secret`
- Scheduled backups: `/var/backups/excalidraw`, retained for 14 days
- Authentication: ExcaliDash local accounts; the first enrolled account becomes
  the administrator

Both images are pinned to immutable multi-architecture OCI-index digests:

- `docker.io/zimengxiong/excalidash-frontend:0.6.0@sha256:4ec5b20c03034b96d37cfb87b5c39e9cc5958441a3abd8dcc413d11dfb11809c`
- `docker.io/zimengxiong/excalidash-backend:0.6.0@sha256:cbdab75f31b21e342b464d6404a454791e5da7452e3614b137021a800fc4cac6`

ExcaliDash provides named drawings, search, collections, history, and portable
import/export. The backend stores diagrams and embedded images in SQLite, so
clearing browser state or replacing either container does not delete saved
drawings. Realtime collaboration is part of ExcaliDash; this deployment adds no
separate collaboration service or public WebSocket endpoint.

## Backup and export

The backend performs an SQLite-safe scheduled backup at 04:00 daily and prunes
files older than 14 days. The backup directory is a host bind mount and survives
container replacement. The database, generated authentication secrets, and
backups must be preserved together for disaster recovery.

For portable application-level recovery, use Dashboard → Export all. ExcaliDash's
archive keeps drawings in the standard `.excalidraw` format and carries embedded
images. Store an export outside Hades before upgrades that change the database
schema.

## Validation

After the attended Podman cutover:

```console
sudo systemctl is-active excalidraw-backend.service excalidraw.service
curl --fail http://127.0.0.1:3100/
sudo test -f /var/lib/excalidraw/excalidraw.db
sudo test -d /var/backups/excalidraw
```

From an approved tailnet client, open the canonical origin, complete first-admin
enrollment, create and rename an expendable drawing, refresh in a second browser,
and export the complete archive. Trigger or wait for a backup, then verify the
result is non-empty before treating persistence as accepted.

## Rollback

Select the previous NixOS generation to restore the previous service definitions.
Keep `/var/lib/excalidraw` and `/var/backups/excalidraw` untouched during software
rollback. If an upgrade changed the schema incompatibly, restore the pre-upgrade
database and both generated secret files before starting the older backend image.
