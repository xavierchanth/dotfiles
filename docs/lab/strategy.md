# Lab Machine Management Strategy

Status: current direction

## Goal

Manage the lab computers from this flake with the roles recorded in the [machine inventory](../hosts.md). Hades, Poseidon, Zeus, Eris, and Charon share one mini lab. This document does not replace the router, NAS, switch, or other existing infrastructure.

## Recommended operating model

| Host | Operating system | Configuration owner |
| --- | --- | --- |
| `eris` | macOS | nix-darwin + Home Manager |
| `zeus` | NixOS target; Ubuntu during transition | NixOS + Home Manager |
| `poseidon` | NixOS target; Ubuntu during transition | NixOS + Home Manager |
| `hades` | NixOS target; Ubuntu during transition | NixOS + Home Manager |

Use one flake with per-host platform metadata. Share policy through modules, but keep hardware and enabled workloads in each host directory.

```text
nix/
  inventory.nix
  hosts/{darwin,nixos}/
  home/
  modules/{darwin,nixos,home,shared}/
```

Nix can run on Ubuntu, but it cannot declaratively own the entire Ubuntu system. During transition, use Nix and Home Manager for packages and user configuration. Keep existing root-level Ubuntu configuration explicit. Migrate to NixOS when ready to have the flake own users, systemd services, containers, firewall rules, and upgrades.

Terraform is unnecessary for these existing machines. Ansible is optional for one-time Ubuntu bootstrap only; it should not become a second permanent source of desired state.

## Workload model

Use three execution forms:

1. NixOS modules and systemd services for software that is packaged cleanly and needs direct host integration.
2. OCI containers for upstream applications such as Forgejo when the container is the simplest supported release artifact.
3. Containers or microVMs for agentic workloads that execute tools or consume untrusted input.

Avoid Kubernetes initially. Three static hosts do not justify its operational cost unless automatic rescheduling, service discovery, and replicated workloads later become real requirements.

## Git and workflow execution

Forgejo is the preferred starting point for a private Git service. Keep the server and its durable data on one selected Linux host, then back up its data and repositories to the existing NAS. Do not run arbitrary CI jobs inside the Forgejo server process.

Install Forgejo runners on separate worker hosts. Label runners by capability, for example:

- `linux-x86_64`
- `linux-agent`
- `macos-arm64`
- `trusted-deploy`

Repository-triggered tests, builds, and maintenance fit Forgejo Actions. Long-running autonomous work should use a separate queue or agent scheduler so CI semantics do not become the general job-control system.

## Agent isolation

Hermes and other agent workers can execute commands and ingest untrusted content. Run each worker with:

- A dedicated unprivileged identity.
- A container or microVM boundary.
- A dedicated workspace instead of the operator home directory.
- No host deployment keys, privileged container socket, or broad NAS mount.
- Explicit network access and narrowly scoped credentials.
- CPU, memory, process, and disk limits.
- Disposable execution state; export only intentional artifacts and durable agent state.

Hermes should have one declared owner among the Linux workers. Choose between Poseidon and Zeus after comparing CPU, RAM, storage, and accelerator availability. The service definition should be reusable so moving ownership is a one-line host configuration change.

## Assigned roles and service placement

- `hades`: headless Podman application host over Tailscale and selected network services.
- `poseidon` and `zeus`: Linux workers with Cage for computer-use workflows.
- `eris`: Mac worker.
- `charon`: existing lab router.
- `nyx`: daily Mac workstation.

These roles are settled; individual service deployments still require capacity
checks and explicit host configuration. Hades's network services remain to be
selected. Keep essential routing and access independent of development containers.
See the [shared Podman plan](podman.md) for lifecycle and rollout steps.

Persistent Lab containers run on Hades under systemd-owned Podman units. Jobs
assigned to a worker use that worker's own execution environment; Hades does not
provide a shared privileged container socket to interactive clients.

Forgejo remains a proposed persistent service; choose its placement after checking
storage and isolation requirements. Assign Hermes and Linux runners across Poseidon
and Zeus from measured capacity. Keep untrusted jobs isolated from Hades's rootful
Podman runtime and persistent service data.

## Deployment lifecycle

1. Change the flake in Git.
2. Evaluate and build the target configuration.
3. Deploy to one named host over SSH.
4. Verify systemd units, containers, health checks, and storage mounts.
5. Roll back to the prior generation if verification fails.

Do not make every host automatically follow the repository head. Use reviewed, explicit deployments. Automated agents may propose changes, but a trusted deployment path applies them.

## Secrets and data

- Use `sops-nix` or `agenix`; keep plaintext secrets out of Git and the Nix store.
- Give each service only its own credentials.
- Store service data outside immutable package paths.
- Back up Forgejo repositories, database, configuration, and agent state to the NAS.
- Test restoration onto a clean host.

## Migration plan

1. Inventory CPU, RAM, disks, accelerators, and current workloads on all hosts.
2. Maintain the per-host system and profile metadata in `nix/inventory.nix`.
3. Use the existing standalone Home Manager outputs during any Ubuntu transition.
4. Package or containerize Forgejo, Hermes, and worker runtimes.
5. Migrate the least critical Ubuntu host to NixOS first.
6. Prove remote deployment, rollback, secret provisioning, and restore.
7. Migrate the remaining Linux hosts individually.
8. Assign individual services within the agreed host roles using measured capacity.

## Reference basis

- [NixOS Manual: systemd and container management](https://nixos.org/manual/nixos/stable/)
- [Forgejo Actions overview and runner model](https://forgejo.org/docs/latest/user/actions/overview/)
- [Forgejo runner isolation and configuration](https://forgejo.org/docs/latest/admin/actions/configuration/)
- [Hermes Agent security and trust model](https://github.com/NousResearch/hermes-agent/security)

## Deployment front doors

Routine deploy-rs, assured Hades rollout, and attended Charon application have intentionally different guarantees. See [deploy.md](deploy.md); do not substitute one for another.
