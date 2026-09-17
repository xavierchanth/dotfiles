# CLIProxyAPI

CLIProxyAPI is a third-party, provider-neutral subscription and API gateway.
It maintains a runtime pool of upstream credentials and presents a stable,
Responses-compatible downstream API. The first rollout exercises one provider
and one client adapter, but neither is part of the gateway architecture.
Upstream providers can change authentication, protocol, product behavior, or
terms independently; treat the service as experimental and revocable.

## Security contract

- Release `v7.3.5` uses the upstream no-plugin Linux artifact pinned by SHA-256.
- `cliproxyapi.service` runs as the dedicated `cliproxyapi` system user with a
  read-only system, no capabilities, restricted namespaces and address
  families, and other systemd hardening.
- Persistent state is `/var/lib/cliproxyapi`, owned by the service with mode
  `0700`. OAuth credentials, per-client tokens, and the loopback management key
  live beneath it. The generated runtime configuration lives under
  `/run/cliproxyapi` and disappears at reboot.
- The service binds plain HTTP only at `127.0.0.1:8317`. It opens no firewall
  port. The control panel, pprof, plugins, discovery, request logs, file logs,
  and usage aggregation are disabled.
- The authenticated Management API remains available only on loopback at
  `/v0/management` as a clean seam for a future separately reviewed dashboard.
  No dashboard is selected, bundled, exposed, or routed in this change.
- WebSocket authentication is enabled. Poseidon and Zeus receive distinct
  bearer tokens generated on Hades at activation time. Rotating one token does
  not invalidate the other.
- Tokens and OAuth files never enter Nix, Git, process arguments, or generated
  documentation. Normal logs exclude request bodies and credentials. Keep
  debug logging disabled.

Gateway may publish only these authenticated data-plane operations for
`cliproxyapi.lab.xavierchanth.xyz`: models, Responses streaming, Responses WebSocket
upgrade, and response compaction beneath `/v1`. It must keep `/healthz`, `/`,
`/management.html`, `/v0/management/*`, and every provider OAuth callback path
local. The local health contract is `GET /healthz`, HTTP 200, with
`{"status":"ok"}`.

## Provider bootstrap

After deployment and before enrolling clients:

1. Reach Hades over authenticated Tailscale SSH and run
   `sudo cliproxyapi-provider-bootstrap codex-device` from the remote terminal
   for the initial provider. Other supported login modes are selected at
   invocation time rather than in declarative Nix.
2. Open the displayed provider URL in Xavier's trusted local browser and enter
   the one-time code. The helper does not put the code in argv or a service log.
3. The upstream refresh credential is written directly to the service-owned
   authentication directory. Confirm its owner and mode without printing it.
4. Start or restart `cliproxyapi.service`, then check
   `curl --fail http://127.0.0.1:8317/healthz`.

The device flow keeps provider sign-in on an authenticated SSH session while
the browser completes the provider challenge from a trusted tailnet client.
It does not expose the loopback management API or management key. If a browser
callback login is used for another provider, forward only that provider's
short-lived callback port over SSH; never add it to Caddy or the firewall.

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
`CLIPROXYAPI_TOKEN`; do not write it into the template, Nix configuration,
service command line, shell history, or JIO project configuration. Verify the
client uses `https://cliproxyapi.lab.xavierchanth.xyz/v1`, the Responses wire API,
and WebSockets. Revoke one client independently with:

```sh
sudo cliproxyapi-client-token rotate poseidon
```

Deliver the replacement out of band, then prove the old token receives HTTP
401 while Zeus continues working.

## Snapshot, restore, update, and rollback

`/var/lib/cliproxyapi` contains bearer tokens and upstream OAuth refresh
credentials. It is intentionally excluded from ordinary unencrypted lab
snapshots. A local snapshot is permitted only as an explicitly encrypted
archive whose decryption key is stored elsewhere. Stop the service first,
encrypt the complete directory without an intermediate plaintext archive, and
record the release beside the encrypted artifact. Test restoration into an
empty temporary directory, checking ownership and `0700`/`0600` modes without
printing file contents.

Without an encrypted snapshot, restore by redeploying the pinned service,
repeating OAuth bootstrap, and enrolling fresh client tokens. This is the
preferred pilot recovery path.

For an update, verify the signed upstream release, replace both the version and
artifact hash, build Hades without activation, review upstream authentication
and route changes, then activate and run the live gates below. Roll back to the
previous NixOS generation and pinned binary. If the credential format migrated,
restore the matching encrypted snapshot or reauthenticate instead of copying
new state into an older release.

## Live gates

Before clients depend on the service, prove all of the following:

1. Loopback health and an authenticated `/v1/models` request succeed.
2. Missing, Poseidon, and Zeus tokens yield 401, success, and success
   respectively; rotating Poseidon invalidates only its old token.
3. A Responses-compatible request streams to completion over HTTP and a
   separate request completes through the Responses WebSocket transport.
4. Gateway rejects health, management, control-panel, root, and callback paths.
5. Service logs contain no bearer token, OAuth code, refresh token, prompt, or
   response body after success and representative failures.
6. A service restart preserves upstream OAuth state and client tokens.
7. The documented reauthentication recovery, and any encrypted restore chosen
   for the pilot, work from clean state.
