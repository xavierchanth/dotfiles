# Lab Hosts

Hades, Poseidon, Zeus, Eris, and Charon share one mini lab. See the
[machine inventory](../hosts.md) for the full fleet and authoritative role overview,
including Nyx, Daedalus, Nike, and Persephone.

## Eris

Eris is the Mac worker and remains on macOS, managed by `darwinConfigurations.eris` plus Home Manager. nix-darwin owns supported system settings and Home Manager owns user tools. Linux services must not depend on it being online; its worker role does not make it the sole deployment origin.

## Linux hosts: Hades, Poseidon, and Zeus

Each host is independently exposed as `nixosConfigurations.<hostname>` with Home Manager for the operator account. The repository now has NixOS configurations for all three; any real-world Ubuntu-to-NixOS transition must still preserve bootable rollback and recovery access.

Hades is assigned shared Podman workloads and selected network services; Poseidon and Zeus
are Linux workers with Cage for computer-use workflows. Hades is headless and
does not include the Cage desktop group. These assignments establish intended roles, not deployed
service status. See the [shared Podman plan](podman.md) for rollout requirements.
Hades also owns the tailnet-only [stable service gateway](service-gateway.md).

For each host:

- Select workloads explicitly in its host module; do not infer assignments from its name.
- Keep durable data outside the Nix store and back it up to the NAS.
- Isolate and resource-limit agent workloads.
- Record CPU, RAM, disks, accelerators, and existing workloads before assigning stable-service or disposable-worker duties.
- Build and deploy independently so one host's failure does not block the others.

## Deployment

The deploy-rs lab set is Eris, Hades, Poseidon, and Zeus, addressed by canonical IP. Charon is OpenWrt and Nyx is only a client. The canonical sequential order is Poseidon, Zeus, Hades, Eris; see [deploy.md](deploy.md).
