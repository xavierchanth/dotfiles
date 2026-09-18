# Shared Docker host

Status: Hades daemon configuration is implemented in the flake; live deployment
and client defaults still require verification.

Hades owns the shared Docker daemon. Nyx and other interactive clients should
default to a named `lab` context using SSH over Tailscale. Keep the daemon on its
Unix socket; SSH carries Docker API requests. Derive managed configuration from
the repository's host and user values. Confirm Hades's actual Tailscale identity
before configuring its endpoint; the LAN address is not a Tailscale endpoint.

The `docker-host` group enables Docker at boot, adds the operator to the Docker
group, and includes Docker in rollout health checks. It uses a Unix socket,
bounded local logs, live restore, and no automatic pruning. Default bridge port
publishing binds to loopback; explicitly choosing a different bind address can
override that default. Access applications through SSH tunnels until exposure
is deliberately configured.

## Workload boundaries

- Hades runs shared development containers and selected persistent services.
- Poseidon and Zeus execute assigned Linux jobs on their own compute and retain
  Cage for computer-use workflows. Hades has no Cage desktop group.
- Eris executes assigned macOS jobs locally.
- Worker jobs must explicitly select their execution environment so an
  interactive Docker default cannot silently move computation to Hades.
- Docker administration grants broad control of the host. Untrusted agent jobs
  must not receive unrestricted access to the shared daemon.

Use distinct Compose project names for independent projects or workspaces.
Coordinate published host ports, even when project names differ. Resource-limit
development workloads so they cannot crowd out persistent services. Keep
important volume data outside disposable build caches and back it up to the NAS;
do not apply broad volume pruning to a shared host.

## Client behavior

If Hades is unavailable, fail visibly and select another context explicitly.
Keep a local runtime optional for offline work and workflows requiring it.

Bind mounts resolve on Hades, not on the client. Projects that live-mount source
need a remote checkout, an explicit synchronization workflow, or local execution.
Build contexts can be transferred to the remote builder; keep them small with
`.dockerignore`. Published ports belong to Hades; use explicit SSH forwarding
when an application needs to appear on the client's localhost. The Docker SSH
connection alone does not forward application ports.

Nyx and Eris are ARM64; the Linux hosts are x86-64. Verify image platform support
and choose build targets explicitly when architecture matters.

## Implementation and rollout

Preflight on 2026-09-12 confirmed Hades runs NixOS 26.05 and is reachable over
Tailscale. It reported 59 GiB total RAM,
58 GiB available RAM, and 857 GiB available on its root disk. Docker was not on
the operator's PATH. Activation requires the operator's interactive sudo password.
These observations are a dated preflight, not ongoing health guarantees.

From the repository root, the routine attended rollout command is:

```console
nix run path:.#deploy -- hades
```

The explicit path source includes new module files before they are tracked in
version control. See [deployment](deploy.md) for credential requirements and the
separate assured Hades workflow. Reconnect SSH after activation to acquire the
operator's new Docker group membership.

1. Inspect Hades's running OS, CPU, memory, free disk, and existing workloads.
   Verify SSH access through its Tailscale identity from Nyx.
2. Add a reusable NixOS Docker group and enable it explicitly for Hades. Set
   operator access, storage policy, and service health checks in the configuration.
3. Configure the named client context through the existing Home Manager structure.
   Preserve explicit context overrides and worker-local execution.
4. Evaluate and build the affected configurations, then deploy Hades first.
5. Verify remote container execution, a representative image build, a named
   volume, and application access over an explicit tunnel.
6. Verify failure when Hades is unreachable and explicit local selection. Exercise
   a worker job to confirm it consumes that worker's compute.
7. Activate client defaults after the daemon and connectivity checks succeed.
   Stop Nyx's local runtime only after representative projects work remotely.

Back out by selecting the previous client context and restoring the previous
configuration. A NixOS rollback does not restore Docker volume contents; preserve
data independently and test restoration before migrating important state.

## References

- [Docker SSH access](https://docs.docker.com/engine/security/protect-access/)
- [Bind-mount behavior](https://docs.docker.com/engine/storage/bind-mounts/)
- [Remote build context guidance](https://docs.docker.com/build-cloud/optimization/)
