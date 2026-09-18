# CLIProxyAPI and CPA Manager Plus

CLIProxyAPI is a third-party, provider-neutral subscription and API gateway.
It maintains a runtime pool of upstream credentials and presents a stable,
Responses-compatible downstream API. The first rollout exercises one provider
and one client adapter, but neither is part of the gateway architecture. CPA
Manager Plus (CPAMP) is the separately packaged operations dashboard for the
gateway. Upstream providers can change authentication, protocol, product
behavior, or terms independently; treat both services as experimental and
revocable.

## Service and trust boundaries

- CLIProxyAPI release `v7.3.5` and CPAMP release `v1.12.14` use their upstream
  Linux release artifacts pinned by SHA-256. Both packages update independently.
- `cliproxyapi.service` and `cpa-manager-plus.service` run as separate,
  unprivileged system users with read-only system views, no capabilities,
  restricted namespaces and address families, and systemd restart policies.
- CLIProxyAPI binds plain HTTP at `127.0.0.1:8317`. CPAMP binds plain HTTP at
  `127.0.0.1:18317`. Neither service opens a firewall port.
- Caddy exposes the authenticated inference allowlist at
  `https://cliproxyapi.lab.xavierchanth.xyz` and the CPAMP administrative origin at
  `https://cpamp.lab.xavierchanth.xyz`. Both origins are tailnet-only.
- The inference origin permits only `/v1/models`, `/v1/responses`, and
  `/v1/responses/compact`. It returns 404 for CLIProxyAPI health, raw management,
  control-panel, root, and provider callback paths. Responses WebSocket upgrades
  and streaming use the allowed `/v1/responses` route.
- CPAMP receives its whole dedicated origin because the embedded application
  owns several UI and API paths. CPAMP authenticates them with its own admin
  key after initial setup. It reaches CLIProxyAPI management directly at
  `http://127.0.0.1:8317`; raw CLIProxyAPI management remains off both client
  and CPAMP public origins.

CLIProxyAPI persistent state is `/var/lib/cliproxyapi` with mode `0700`.
Upstream authentication credentials, per-client tokens, and its loopback management key live
beneath it. Its generated runtime configuration lives under `/run/cliproxyapi`
and disappears at reboot. Request/file logging, usage aggregation, pprof,
plugins, discovery, and the bundled control panel are disabled. WebSocket
authentication is enabled.

The management key contains a 15-byte label plus 24 random bytes encoded as
hex, remaining below bcrypt's 72-byte input limit while retaining 192 bits of
randomness. Startup deterministically shortens the obsolete 64-hex-character
key format once, without printing or randomly rotating it; valid current keys
are reused unchanged.

CPAMP persistent state is `/var/lib/cpa-manager-plus` with mode `0700`.
`usage.sqlite` contains configuration and operational history; `data.key`
encrypts the saved CLIProxyAPI management credential; `admin-key` is the
recoverable input whose salted verifier is stored in SQLite. The service uses
`UMask=0077`, disables its background update check, and restricts CORS to its
canonical origin. Secrets never enter Nix, Git, service arguments, generated
documentation, or ordinary unencrypted backups.

CPAMP's process namespace bind-mounts that state directory at writable `/data`
because upstream stores usage-import sessions there. A pre-start probe writes
through `/data`, confirms the same inode appears below
`/var/lib/cpa-manager-plus`, and cleans it up before the server starts. Both
services bound their readiness waits to 75 seconds and use a three-attempt
systemd start limit, so repeated failure ends the activation job instead of
creating an unbounded restart loop.

## Provider bootstrap and account policy

The operational minimum is two distinct enabled upstream accounts. Provider
choice and credentials are mutable runtime state: they do not belong in Nix or
Git. Bootstrap each account separately over authenticated Tailscale SSH to
Hades. The initial rollout uses the `codex-device` login mode, while the helper
also exposes the other login modes supported by the pinned release:

```sh
sudo cliproxyapi-provider-bootstrap codex-device
sudo cliproxyapi-provider-bootstrap codex-device
sudo cliproxyapi-account status
```

For each login, open the displayed provider URL in Xavier's trusted local
browser and enter the one-time code. The helper writes authentication state
directly to the service-owned auth directory with a restrictive umask; it does
not place the code or credential in argv or the journal. This SSH/Tailscale
path does not expose CLIProxyAPI's loopback management API or management key.

`cliproxyapi-account status` deliberately prints only operational metadata,
including filename, provider/type, upstream identity, operator note,
enabled/available state, priority, quota, cooldowns, and request
success/failure counters. Confirm that
there are at least two enabled upstream files with distinct `email` or `account`
identities. Assign durable human labels and explicit priorities using the
stable filenames returned by status:

```sh
sudo cliproxyapi-account note ACCOUNT_FILE.json primary-subscription
sudo cliproxyapi-account note OTHER_FILE.json secondary-subscription
sudo cliproxyapi-account priority ACCOUNT_FILE.json 10
sudo cliproxyapi-account priority OTHER_FILE.json 10
```

Normal policy is `round-robin` with one-hour session affinity. Cold sessions
are distributed among eligible credentials; a session stays on its selected
credential for cache continuity and automatically fails over if that credential
becomes unavailable. Upstream quota and cooldown behavior remains active.
Priorities select a preferred tier when they differ. For a primary/reserve
policy, give the primary a higher priority than the reserve. Operators can
remove one account from eligibility without deleting authentication state:

```sh
sudo cliproxyapi-account disable ACCOUNT_FILE.json
sudo cliproxyapi-account enable ACCOUNT_FILE.json
```

Poseidon and Zeus have separately revocable downstream API keys, but those
keys share the same eligible upstream account pool. The pinned release does
not bind a downstream key to a particular upstream account.

If a provider requires a browser callback, forward only that short-lived
callback port over the authenticated SSH session. Keep callback listeners out
of Caddy and the firewall.

## CPAMP first setup

After both services and the gateway are healthy, keep an authenticated
Tailscale SSH session to Hades open. CPAMP is the normal day-to-day web UI;
`cliproxyapi-account` remains the local bootstrap, recovery, and automation
surface.

1. In the SSH terminal, retrieve the CPAMP login key with
   `sudo cpa-manager-plus-admin-key show`.
2. Open `https://cpamp.lab.xavierchanth.xyz/management.html` from the same
   trusted tailnet client and sign in over HTTPS.
3. Retrieve the CLIProxyAPI management key only in the SSH terminal with
   `sudo cliproxyapi-account show-management-key`. Enter it directly into the
   CPAMP setup form; do not forward port 8317, expose `/v0/management`, save the
   key in a client file, or put it in shell history. Clear any temporary
   clipboard immediately after submission.
4. Complete setup with CPA URL `http://127.0.0.1:8317` and the CLIProxyAPI
   management key. Enable request monitoring and the HTTP usage queue.
5. Confirm CPAMP reports all labeled upstream identities, per-account quota and
   health, request attribution, enabled state, and the active routing policy.
6. Inspect `/var/lib/cpa-manager-plus` without printing contents and verify that
   `usage.sqlite` and `data.key` exist with service ownership and restrictive
   modes. The CLIProxyAPI management key is now encrypted in SQLite.

Rotate the CPAMP login credential with
`sudo cpa-manager-plus-admin-key rotate`; the helper stops the writer, changes
the SQLite verifier using a file input, replaces the protected recovery file,
and restarts the service.

## Client enrollment and revocation

The gateway is client-neutral. For the initial rollout only, a secret-free
Codex adapter example is installed at `/etc/cliproxyapi/codex-client.toml`.
Merge it into the selected client configuration on Poseidon or Zeus. Retrieve
only that downstream principal's token from a trusted Hades terminal:

```sh
sudo cliproxyapi-client-token show poseidon
sudo cliproxyapi-client-token show zeus
```

Place the value in the client's protected runtime secret source as
`CLIPROXYAPI_TOKEN`. The client URL is
`https://cliproxyapi.lab.xavierchanth.xyz/v1`, using the Responses wire API and
WebSockets. Revoke one client independently with:

```sh
sudo cliproxyapi-client-token rotate poseidon
```

Deliver the replacement out of band, then prove the old token receives HTTP
401 while Zeus continues working.

## Snapshot and restore

Both state directories contain secrets or sensitive operational history and
are excluded from ordinary unencrypted backups.

For CPAMP, stop `cpa-manager-plus.service` before copying. Snapshot the whole
`/var/lib/cpa-manager-plus` directory as one encrypted unit so
`usage.sqlite`, `usage.sqlite-wal`, `usage.sqlite-shm`, any journal file, and
the matching `data.key` stay together. Losing `data.key` makes the saved CPA
connection unrecoverable; exposing it together with SQLite exposes the saved
management credential. Preserve `admin-key` with the same secret handling.

For CLIProxyAPI, stop `cliproxyapi.service` before creating an encrypted
snapshot of `/var/lib/cliproxyapi`. Without that snapshot, recover by repeating
provider bootstrap and enrolling new client tokens. This reauthentication path is
preferred during the pilot.

Restore into an empty state directory while both services are stopped, repair
ownership and `0700`/`0600` modes without printing contents, start
CLIProxyAPI first and CPAMP second, and run all live gates. Never combine an
older `data.key` with a newer database or restore only one SQLite sidecar.

## Update and rollback

Update CLIProxyAPI and CPAMP independently. Verify the immutable upstream
release, replace its version and architecture hashes, evaluate and build Hades
without activation, review authentication/storage migrations, take the
service-specific encrypted snapshot, activate, and run the live gates.

For CPAMP, stop the service before the pre-update snapshot because startup can
perform SQLite migrations. A package rollback is safe only with state that is
compatible with that package. Roll back the NixOS generation, then restore the
matching stopped-state snapshot of SQLite/WAL/SHM/journal plus `data.key` when
the newer version migrated storage. For CLIProxyAPI credential-format changes,
restore its matching encrypted snapshot or reauthenticate instead of copying
new provider credential files into an older release.

## Live gates

Before clients depend on the services, prove all of the following:

1. `GET http://127.0.0.1:8317/healthz` returns HTTP 200 with `status=ok` and
   `GET http://127.0.0.1:18317/health` returns HTTP 200 with `ok=true` and
   `service=cpa-manager-plus`.
2. Account status reports at least two distinct, enabled upstream identities and
   CPAMP shows their quota, health, enable/disable control, routing policy, and
   correctly attributed test requests.
3. Missing, Poseidon, and Zeus inference tokens yield 401, success, and success;
   rotating Poseidon invalidates only its old token.
4. A Responses request streams to completion over HTTP and a separate request
   completes through the Responses WebSocket transport.
5. The inference origin returns 404 for health, management, control-panel,
   root, and callback paths. The CPAMP origin serves its authenticated UI and
   never reveals the raw CLIProxyAPI management key to an ordinary client.
6. Service logs contain no bearer token, provider/device code, refresh token,
   management key, admin key, prompt, or response body after successful and
   representative failing requests.
7. Restarting both services preserves provider credential files, two-account metadata,
   downstream client tokens, CPAMP login, encrypted CPA connection, SQLite
   history, and `data.key`.
8. The documented reauthentication recovery and encrypted CPAMP restore work
   from clean state before the pilot is considered recoverable.
