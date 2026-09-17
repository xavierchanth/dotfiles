# Service gateway

Hades owns the local half of the Lab's stable HTTPS ingress. Caddy accepts TLS
only on `127.0.0.1:8443`; the later Tailscale Service activation forwards raw
TCP from `svc:lab` port 443 to that loopback listener. Caddy therefore receives
the original TLS ClientHello, selects a certificate and route by SNI, and keeps
its private CA keys on Hades.

| Stable origin | Upstream | Health path | Application owner |
| --- | --- | --- | --- |
| `https://lab.xavierchanth.xyz` | `http://127.0.0.1:3000` | `/api/healthcheck` | Homepage |
| `https://executor.lab.xavierchanth.xyz` | `http://127.0.0.1:4788` | `/api/health` | Executor |
| `https://plane.lab.xavierchanth.xyz` | `http://127.0.0.1:8080` | `/` | Plane |
| `https://codex.lab.xavierchanth.xyz` | `http://127.0.0.1:8317` | `/healthz` | CLIProxyAPI |

The reusable `service-gateway` group requires the `tailscale` group. Its typed
`dotfiles.serviceGateway.routes` option accepts only IPv4 or IPv6 loopback
upstreams, a valid TCP port, an absolute health path, and an optional systemd
unit for startup ordering. The gateway contract also publishes an unadvertised
Tailscale Services configuration at
`dotfiles.serviceGateway.tailscaleService.configFile`:

```json
{
  "version": "0.0.1",
  "services": {
    "svc:lab": {
      "advertised": false,
      "endpoints": {
        "tcp:443": "tcp://127.0.0.1:8443"
      }
    }
  }
}
```

Generating this file is A0 preparation. Applying it, advertising or approving
the service, assigning DNS, and deploying the host are separate authorized
steps.

## Ingress invariants

- Caddy binds only `127.0.0.1:8443`; the NixOS firewall opens no TCP 80, TCP
  443, or UDP 443 path.
- Automatic HTTP redirects are disabled, so Caddy does not create an HTTP
  listener. HTTP/3 is disabled by allowing only HTTP/1.1 and HTTP/2.
- Strict SNI host checking is enabled and there is no catch-all virtual host.
  Unknown or missing SNI fails during TLS rather than reaching an application.
- Every named origin is proxied without path rewriting or a second
  authentication layer. Responses are unbuffered for SSE and other long-lived
  streams.
- The CLIProxyAPI origin is deny-by-default. It proxies only `/v1/models`,
  `/v1/responses`, and `/v1/responses/compact`, preserving each complete path,
  query, streaming response, and WebSocket upgrade. Every other path returns
  404 at Caddy. The root, `/healthz`, management UI and API, plugin management
  resources, and provider OAuth callbacks therefore remain accessible only
  through CLIProxyAPI's loopback listener on Hades.
- Plane's application proxy retains ownership of its 10 MiB request-body limit
  and WebSocket application routing; Caddy adds neither a second size limit nor
  path-specific rewrites.
- Caddy owns TLS and uses its internal CA. Tailscale performs raw TCP
  forwarding and does not terminate TLS.

The gateway owns stable hostnames, TLS termination, route health checks, and
whole-origin proxy behavior. Each application owns authentication,
authorization, session lifecycle, API compatibility, and the semantics of its
health endpoint.

## Phase 0 observations

On 2026-09-16, Hades, Poseidon, and Zeus were running Tailscale 1.102.3. Hades
reported no local `svc:lab` configuration (`tailscale serve get-config` returned
`{}`), no advertised services, and no Serve listener. `caddy.service` and
`executor.service` were inactive and no process was listening on ports 80, 443,
or 8443. Poseidon independently had an existing node-scoped HTTPS Serve rule on
port 443; it is outside this gateway contract.

The admin policy page required a fresh interactive login, so the tailnet's
service resource, tag ownership, grants, and auto-approval rules remain an A1
console verification. A Tailscale Service host must use a tag identity; Hades
currently has a user-owned node identity and advertises no tags.

## Internal CA bootstrap and recovery

Caddy persists its CA under `/var/lib/caddy`. After startup, the gateway anchors
the SHA-256 digest of the generated public root at:

```text
/var/lib/caddy/.dotfiles-root-ca.sha256
```

Every subsequent Caddy start compares the current root with that anchor and
fails the unit if the CA changed unexpectedly. Inspect the current fingerprint
with `service-gateway-ca-fingerprint`. Export only the verified public root with:

```sh
sudo -u caddy service-gateway-ca-export ./hades-caddy-root.pem
```

The export refuses to overwrite a different certificate. Compare its printed
fingerprint over the authenticated Tailscale SSH channel before pinning the PEM
in Dotfiles. Never copy the sibling `root.key`; private CA material remains only
on Hades.

Back up and restore all of `/var/lib/caddy` as one unit. A valid recovery keeps
the root certificate, private key, and `.dotfiles-root-ca.sha256` together. A
missing or mismatched member is a stopped gateway, not an implicit CA rotation.
Intentional CA rotation requires an explicit trust rollout to every managed
client before the old root is retired.

## Validation

Before deployment, build the focused assertions and the Hades system:

```sh
nix build --no-link --no-write-lock-file path:.#checks.x86_64-linux.service-gateway
nix build --no-link --no-write-lock-file path:.#nixosConfigurations.hades.config.system.build.toplevel
```

After an authorized A1 activation, verify the local applications and Caddy
before advertising the service:

```sh
curl --fail http://127.0.0.1:3000/api/healthcheck
curl --fail http://127.0.0.1:4788/api/health
curl --fail --header 'Host: plane.lab.xavierchanth.xyz' http://127.0.0.1:8080/
curl --fail http://127.0.0.1:8317/healthz
sudo systemctl is-active tailscaled.service homepage.service executor.service plane.service cliproxyapi.service caddy.service
sudo ss -ltnp | grep '127.0.0.1:8443'
curl --fail --resolve lab.xavierchanth.xyz:8443:127.0.0.1 \
  --cacert ./hades-caddy-root.pem https://lab.xavierchanth.xyz:8443/
for path in / /healthz /management.html /v0/management /anthropic/callback /codex/callback /antigravity/callback /callback /devin/callback; do
  test "$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --resolve codex.lab.xavierchanth.xyz:8443:127.0.0.1 \
    --cacert ./hades-caddy-root.pem \
    "https://codex.lab.xavierchanth.xyz:8443$path")" = 404
done
```

Confirm there are no listeners on host ports 80 or 443 and that an unknown SNI
name fails the TLS handshake. Then apply the generated Tailscale configuration,
verify it, and request service-host approval as separate A1 actions.

## Remaining rollout

### A1: tailnet service and origin

1. Verify or create the `svc:lab` resource with interface `tcp:443` and a
   tag-owned Hades identity in the Tailscale admin console.
2. Review grants and the service auto-approver; approve the Hades advertisement
   only after the loopback gateway checks pass.
3. Apply the generated service configuration, advertise Hades, record the
   TailVIP, and verify raw TCP reaches `127.0.0.1:8443`.
4. Point the Namecheap A records for `lab.xavierchanth.xyz` and
   `*.lab.xavierchanth.xyz` at that TailVIP.

### A2: client trust

1. Export the authenticated public root and compare its SHA-256 fingerprint.
2. Pin the PEM in Dotfiles and install it declaratively in managed NixOS and
   macOS system trust stores. Rebuilds must use the pinned PEM and never fetch a
   trust root dynamically.
3. Verify Safari and Chromium system trust, configure Firefox enterprise-root
   import where needed, and install the iOS profile followed by the manual full
   trust toggle.
4. Test Homepage, Executor, and Plane from each intended client through the stable
   hostnames.

## Rollback contract

Before service advertisement, rollback is simply the previous NixOS generation;
no client-visible gateway exists. After advertisement, drain `svc:lab` on Hades
first so it accepts no new connections, then roll Hades back and verify the
previous units. Keep the service resource and DNS records while a known-good
host will resume the same contract; otherwise remove the DNS records and clear
the service advertisement together to avoid a dead stable origin.

Ordinary rollback preserves `/var/lib/caddy`, including the root key and
fingerprint anchor. It never deletes or regenerates CA state. If restored CA
state fails the anchor check, keep the gateway drained until the original state
is recovered or an intentional client-trust rotation is completed.
