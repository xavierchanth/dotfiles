# Shared Podman host

Hades runs the Lab's OCI workloads with rootful Podman managed by native NixOS
`virtualisation.oci-containers` units. Docker, the Docker compatibility command,
and the Docker-compatible socket are disabled. Containers are lifecycle-owned by
systemd and use Podman's default bridge with DNS enabled for container-name
resolution.

## Workload boundary

- `homepage.service` runs Homepage at `127.0.0.1:3000`.
- `executor.service` runs Executor at `127.0.0.1:4788`.
- `excalidraw-backend.service` runs the private ExcaliDash API and SQLite store.
- `excalidraw.service` runs the ExcaliDash frontend at `127.0.0.1:3100`.
- Caddy, CLIProxyAPI, and CPA Manager Plus remain native systemd services.
- Published application ports remain loopback-only; Caddy owns tailnet ingress.

The operator uses `sudo podman` for inspection. No user receives a privileged
container socket. Automatic pruning stays disabled so rollback and incident
inspection cannot silently lose images or stopped container evidence.

## Required two-activation cutover

Homepage and Executor were never configured with user data, so their Docker
containers can be recreated rather than migrated. Version Control must publish
two independently buildable revisions; do not deploy the final combined working
tree as the first cutover.

The first revision contains only the Podman host migration:

- replace `docker-host` with `podman-host` on Hades;
- convert Homepage and Executor to native OCI-container units;
- preserve their systemd names, loopback ports, and backup behavior;
- exclude the `excalidraw` host group, containers, route, private DNS name, and
  Homepage link.

The second revision adds persistent ExcaliDash, its route, private DNS name,
Homepage entry, storage, backups, documentation, and tests.

Cut over in this order:

1. Inventory all Docker containers and confirm Homepage and Executor are the only
   managed workloads. Stop if an unmanaged container exists.
2. Stop `homepage.service` and `executor.service` under the old generation so
   their Compose definitions remove the containers and release ports 3000 and
   4788. Keep `/var/lib/docker` intact through acceptance.
3. Build and activate the first, Podman-only revision. Verify `podman.socket`,
   Homepage, and Executor. Confirm there is no `excalidraw.service`, no container
   on port 3100, and no ExcaliDash route or private DNS answer.
4. Verify Caddy, CLIProxyAPI, CPA Manager Plus, and the tailnet gateway were not
   restarted into a failed state.
5. Build and activate the second, ExcaliDash revision. Enroll the administrator,
   create an expendable diagram, export it, and confirm a scheduled backup is
   produced.

If the first activation fails, select the previous NixOS generation, start
Docker, and start the old Homepage and Executor units. If only the second
activation fails, roll back to the accepted Podman-only generation; Homepage and
Executor remain on Podman while ExcaliDash is withdrawn. Because
`/var/lib/docker` is preserved until both stages are accepted, the prior Compose
workloads remain recoverable. Removing Docker storage is a separate
post-acceptance operation.

## Validation

Before activation, evaluate the focused checks and build Hades without switching
the host. During the attended cutover, verify:

```console
sudo systemctl is-active podman.socket homepage.service executor.service
sudo podman ps --format '{{.Names}} {{.Status}} {{.Ports}}'
curl --fail http://127.0.0.1:3000/api/healthcheck
curl --fail http://127.0.0.1:4788/api/health
```

After ExcaliDash is enabled, also verify its frontend, database, backup directory,
and private origin as described in [Excalidraw](excalidraw.md).
