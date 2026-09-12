# Lab deployment

## Three deliberately separate paths

* **Routine:** `nix run github:xavierchanth/dotfiles#deploy -- HOST` uses the deploy-rs CLI and activator pinned by this flake. It is convenient, not equivalent to the assured path.
* **Assured Hades:** `--assure hades` is unavailable while Hades selects credential-requiring Mise tools. The separate `lab-update` path does not stage those credentials; use routine deployment for the current host composition.
* **Router:** Charon is never deploy-rs. Render with `just openwrt-render`; attended mutation is `nix run .#openwrt-apply-charon -- --apply`.

Routine commands need a Nix-capable Linux or macOS client, personal SSH credentials for `chant` for credential staging, and the selected deployment account's SSH key and real sudo password on the target. Linux hosts migrate from `chant` to `deploy` using the staged procedure below. Mutating `switch` and NixOS `--test` rollouts of hosts composed with `mise-workstation` also require a local `gh auth token` (an explicit `DEPLOY_GITHUB_TOKEN` is intended for controlled automation). The existing local `gh` token may be long-lived; only its tightly bounded remote file exposure is ephemeral. Acquisition happens once before a selected rollout; failure occurs before evaluation or SSH. The token is sent only over SSH stdin using each requiring host's inventory route (currently all four computers), consumed and unlinked by Home Manager, and best-effort removed on every wrapper exit. It is never placed in inventory, argv, the Nix store, or deploy-rs' environment. Linux inventory keys remain their canonical SSH hostnames. Eris is deliberately routed by inventory metadata to its LAN address (`192.168.8.202`) with `ProxyJump=hades`, so it does not depend on Eris Tailscale being available during migration. Root SSH remains disabled. `interactiveSudo` gives the password directly to remote sudo; this repository neither stores it nor grants NOPASSWD. Target-side `remoteBuild` is enabled, so the target must trust/signature-accept everything needed to realize the closure. No `trusted-users` change is made.

## Commands

`just deploy linux` (or `just deploy-linux`) selects only the NixOS hosts in
inventory order: Poseidon, Zeus, then Hades. It stops at the first failure and
never contacts Eris. `just deploy --dry-activate linux`, `just deploy --test linux`,
and `just deploy --boot linux` select the same Linux hosts with the respective
activation mode. A selected host cannot initiate its own group rollout.

### Dedicated Linux deployment account

Hades, Poseidon, and Zeus provision a separate `deploy` account. Its public key is
declared in `nix/deployment.nix`; its private key stays on the client at the
configured home-relative `identityFile`. The account uses password-confirmed
sudo through the wheel group. SSH password login remains disabled, and the
deployment key cannot forward ports or agents. Nix trusted-user permissions are
unchanged. This separates operational identities; it does not isolate a client
account that can access both the personal and deployment keys.

Migration is deliberately two-stage. Each Linux host starts with
`deployment.useDedicatedUser = false` in `nix/inventory.nix`, so existing `chant`
access installs the account before any command tries to use it. Both Macs retain
their existing account and deployment behavior.

Create and unlock the separate client key if it does not already exist:

```sh
ssh-keygen -t ed25519 -a 64 -f ~/.ssh/id_ed25519_dotfiles_deploy -C "home-lab deployment"
ssh-add ~/.ssh/id_ed25519_dotfiles_deploy
```

Add only its `.pub` content to `authorizedKeys` in `nix/deployment.nix`. For each
Linux host, starting with Poseidon, deploy the bootstrap configuration and set the
new account's password directly in your terminal. For example:

```sh
just deploy poseidon
ssh -t chant@poseidon 'sudo passwd deploy'
ssh -o ControlMaster=no -o ControlPath=none -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519_dotfiles_deploy deploy@poseidon 'id; command -v nix; nix --version'
ssh -t -o ControlMaster=no -o ControlPath=none -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519_dotfiles_deploy deploy@poseidon 'sudo -k; sudo -v'
```

The last command must request the new deployment account's password. Never put
that password in the repository, Nix expressions, or command arguments. Keep a
working `chant` recovery session while verifying the new account.

After these checks succeed, set only that host's `useDedicatedUser` to `true`,
run `nix run .#deploy -- probe poseidon`, then `just deploy poseidon` again. The
second deployment validates the new transport and password persistence. Repeat
for Zeus and Hades. After the staged migration, `just deploy linux` updates all
three together. `just deploy lab` also includes Eris.

GitHub credential staging and cleanup still connect as `chant`, and Home Manager
still runs for `chant`. The deployment wrapper checks that personal account's
Home Manager unit even when its build/activation connection uses `deploy`.
Credential cleanup after a lost SSH connection remains best effort. The separate
`lab-update` path selects the same deployment user and key as the routine
wrapper. Invoke its packaged version with `nix run .#lab-update -- --dry-run hades`
(or omit `--dry-run` for its attended workflow). Direct execution of the source
script refuses to guess an identity; its existing credential limitations still apply.

For recovery, restore the affected host's `useDedicatedUser = false` and redeploy
through `chant`. Retain the personal key and account throughout migration.

### Routine commands

```console
nix run github:xavierchanth/dotfiles#deploy -- --help
nix run github:xavierchanth/dotfiles#deploy -- hades             # switch (default)
nix run github:xavierchanth/dotfiles#deploy -- --dry-activate hades
nix run github:xavierchanth/dotfiles#deploy -- --test hades      # NixOS only; also --boot
nix run github:xavierchanth/dotfiles#deploy -- probe hades
```

Credential staging uses a mode-0600, owner-checked file under `/run/dotfiles-deploy/chant`, with a similarly checked per-user state-directory bootstrap fallback until the tmpfiles rule exists. Files are bounded by age, size, and token syntax; unsafe or stale files are deleted. Local/reboot activation may fall back briefly to local `gh auth token`, then continue anonymously when unavailable. `--dry-activate` never stages (and may warn), while `--boot`, probes, and the assured Hades path neither acquire nor stage.

The whole-lab sequence comes from canonical inventory (`poseidon`, `zeus`, `hades`, `eris`) and is sequential and fail-fast. Default switch and `--dry-activate` support the full fleet. `--test` and `--boot` are refused for Eris, and are refused for `lab` before any host is evaluated or contacted: pinned deploy-rs repoints the Darwin system profile in those modes without running activation, which is unsafe and can leave the profile inconsistent with the live system. Eris deployment uses the inventory-derived LAN address `192.168.8.202` through Hades; update inventory rather than embedding a new address in commands or code. Running on a lab member is refused rather than SSHing to itself; use another arbitrary Nix client. Nyx is not a target.

The probe asks for explicit confirmation, then copies only a trivial `.drv` over `ssh-ng`; it performs no activation. This narrowly tests whether the target's remote-build derivation transfer/build prerequisites work; it is not a general signature-trust audit. If it fails, establish an approved signed cache/key or use the target's existing trust policy—do not add broad `trusted-users` or passwordless sudo.

Before routine activation the wrapper deep-forces and JSON-evaluates the complete selected deploy node without building it, then passes `--skip-checks`: deploy-rs' stock checks would realize foreign-system closures. Every deploy-rs process runs in a private local process group; after any return or signal the wrapper terminates and, after a bounded grace period, kills its surviving local transports before returning. This cleanup covers only local descendants (such as detached SSH clients). It cannot prove that remote activation stopped: reconnect freshly and check the target and magic-rollback result before retrying. If even SIGKILL cleanup exceeds its bounded timeout, the supervisor fails explicitly; treat remote state as unknown. Automatic rollback and magic rollback are enabled for NixOS, but are weaker than `lab-update` and cannot guarantee recovery after boot/network/storage failure. Magic rollback is disabled on Darwin because its watcher is not portable. Darwin activation can mutate `/etc/synthetic.conf`/loader-related state outside a generation; rollback may not undo such changes.

## Recovery

### Activation prerequisites and retries

Lab Home Manager generations carry their selected Stow packages in the Nix
closure. Activation stages them under `~/.local/share/dotfiles/stow` and migrates
only links owned by those packages. The original `~/.dotfiles` checkout stays
untouched. When the deployed source changes, the previous managed tree is kept
in a `stow-backup-*` directory beside it. Nyx continues to use its editable
checkout directly. Regular files and unrelated links remain protected by Stow's
conflict checks.

Linux Mise activation explicitly uses Node binaries with the configured
`nix-ld` loader. Other tools can still require builds, so a cold install may take
time. The pinned Mise version does not reliably resolve the `node = "lts"`
alias from the existing lockfile; this change does not claim fully locked tool
installation.

Before a mutating Linux rollout, the wrapper checks for existing activation
processes and an active Home Manager installation. It refuses to overlap that
work, including detached deploy-rs waiters from an interrupted attempt. This is
a preflight check, not an atomic lock between independently started clients.
Do not start concurrent deployments of the same host.

Read progress using `ssh HOST 'journalctl -fu home-manager-chant -o cat'`.
After an interrupted rollout, inspect processes and service state before retrying.
Do not remove a live activation lock. Detached privileged processes may require
an attended sudo cleanup after their ownership and activity are established.

The pinned deploy-rs rollback expects the old generation to contain
`deploy-rs-activate`. A generation originally installed through nixos-rebuild
may lack it. In that case, rollback can restore the profile link but fail to
reactivate the old system. The final generic "rolled back" message is insufficient:
check the error above it, Home Manager status, and the running generation. A
deploy-rs profile is a wrapper, so compare its resolved `bin/switch-to-configuration`
with the running generation's equivalent rather than comparing directory names.

Use console/out-of-band access, select an older NixOS boot generation (or restore the previous system profile), repair SSH/network/sudo, and retry from a different client. On Darwin, use local `darwin-rebuild` and manually repair loader/synthetic configuration if needed. Never assume an invocation follows repository head: a remote `nix run github:...` evaluates the pinned revision it fetched, while `nix run .` uses the current checkout/store source.


## First headless Eris migration

Perform the first migration attended and in this order:

1. On Eris, enable **System Settings > General > Sharing > Remote Login**, restricted to the named admin user(s). Also enable **Screen Sharing**, again selecting named admin users only (not “All users”). There is currently no supported nix-darwin or Apple CLI interface for enabling Screen Sharing; do not use legacy `kickstart` hacks.
2. From the deployment client, verify the route before activation: `ssh -J hades chant@192.168.8.202`. Resolve host-key warnings deliberately rather than bypassing verification.
3. Deploy Eris through the inventory route: `nix run .#deploy -- eris`. Homebrew activation uses `cleanup = uninstall`, so this removes the obsolete GUI `tailscale-app`; running both implementations is unsupported. Removal and enrollment of open-source tailscaled may create a different Tailscale node identity.
4. Once, interactively on Eris after activation, run `sudo tailscale up` and complete enrollment. Never place an auth key in Nix, Git, the Nix store, environment committed by this repository, or command-line arguments.
5. Verify SSH and Screen Sharing after logout, then after a reboot, before relying on headless access. No automatic console login is configured.

For Screen Sharing from outside the LAN, first create a local tunnel through Hades: `ssh -N -L 5900:192.168.8.202:5900 hades`, then connect Screen Sharing to `vnc://localhost:5900`. Screen Sharing is available at the macOS login window after normal startup, but not before FileVault has been unlocked. Boot-time Apple's OpenSSH and the open-source tailscaled LaunchDaemon likewise cannot overcome FileVault's pre-boot unlock boundary.
