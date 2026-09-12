# Machine inventory

This is the human-readable inventory of personal machines and their intended
roles. Hades, Poseidon, Zeus, Eris, and Charon live together in the same mini lab.
Role assignments describe the agreed direction; they do not establish that a
service has been deployed or that a host is currently reachable.

`nix/inventory.nix` owns configuration targets and platform metadata;
`nix/lab.nix` owns lab addresses and deployment membership. Record unmanaged
machines here without adding placeholder flake targets.

| Host | Hardware / operating system | Role | Repository management |
| --- | --- | --- | --- |
| Nyx (`nyx`) | MacBook Air / macOS | Daily Mac workstation; default Docker client of Hades | nix-darwin + Home Manager |
| Hades (`hades`) | Linux / NixOS target | Headless shared Docker host and selected network services | NixOS + Home Manager configuration |
| Poseidon (`poseidon`) | Linux / NixOS target | Linux worker with Cage for computer-use workflows | NixOS + Home Manager configuration |
| Zeus (`zeus`) | Linux / NixOS target | Linux worker with Cage for computer-use workflows | NixOS + Home Manager configuration |
| Eris (`eris`) | Mac / macOS | Mac worker | nix-darwin + Home Manager |
| Charon (`charon`) | OpenWrt | Mini-lab router | Repository-managed OpenWrt workflow |
| Daedalus (`daedalus`) | Framework laptop / Windows or Linux | Semi-retired; future assignments remain open | No configuration target |
| Nike (`nike`) | Gaming PC / Windows | Gaming; available for possible future Windows work | Unmanaged; no configuration target |
| Persephone (`persephone`) | Mobile phone / iOS | Main mobile phone | Unmanaged; no configuration target |

## Execution policy

Hades is the intended shared default Docker destination over Tailscale, using
SSH to access its daemon. Client machines share Hades's images, build cache,
containers, ports, and volumes. A command submitted from a worker to Hades runs
on Hades; jobs assigned to Poseidon, Zeus, or Eris use that worker's own execution
environment. Any local Docker runtime must be selected explicitly for those jobs.

An unreachable Hades should produce an error, with an explicit switch to a local
runtime when needed. Automatic fallback could start a separate instance of a
stateful service with different data.

Charon retains the router role. Specific network services on Hades remain to be
selected; essential routing and access to Hades must survive development Docker
failures. Daedalus and Nike have no worker services assigned yet.

## Operational documentation

- [Lab hosts](lab/hosts.md): configuration and deployment boundaries.
- [Lab strategy](lab/strategy.md): service placement, isolation, and lifecycle.
- [Shared Docker host](lab/docker.md): intended behavior and rollout checks.
- [Deployment](lab/deploy.md): supported deployment workflows.
