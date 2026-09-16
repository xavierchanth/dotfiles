# Service gateway

Hades is the Lab's stable HTTPS service gateway. Caddy exposes named service
origins only to the tailnet and proxies each complete origin to an HTTP listener
on loopback. The first route is:

| Stable origin | Upstream | Health path | Application owner |
| --- | --- | --- | --- |
| `https://executor.lab.xavierchanth.xyz` | `http://127.0.0.1:4788` | `/api/health` | Executor |

The reusable `service-gateway` group requires the `tailscale` group. Its typed
`dotfiles.serviceGateway.routes` option accepts only IPv4 or IPv6 loopback
upstreams, a valid TCP port, an absolute health path, and an optional existing
systemd unit for startup ordering. Hades is the only host that selects the
group. Agent Services can add its route after its unit name and service contract
are settled; Cage and stdio transports are not direct gateway routes.

## Stable-service contract

The gateway owns the stable hostname, tailnet-only ingress, TLS termination,
active upstream health checks, and transparent whole-origin proxy behavior. It
does not rewrite paths, impose a request-body cap, strip application headers, or
add a second authentication layer. Responses are unbuffered so SSE and other
long-lived streams are delivered immediately, and no short stream timeout is
configured.

The application behind a route owns authentication, authorization, session and
token lifecycle, API compatibility, and the semantics of its health endpoint.
For the first route, Executor remains the sole owner of those concerns. A new
stable route requires an explicit application owner and a documented health
contract before it is added to this module.

## Internal CA bootstrap

This slice uses Caddy's internal CA. Every tailnet client must trust the public
root certificate before browsers and API clients will accept the service
certificate. After the first successful Caddy start, copy only this public file
from Hades:

```text
/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt
```

Install it in the operating-system trust store and, where applicable, the
browser's independent trust store. Never copy Caddy's private CA key. Replacing
or deleting `/var/lib/caddy` rotates trust and requires redistributing the new
root certificate. Migration to publicly trusted or tailnet-issued certificates
is a separate gateway change.

## Validation

Before deployment, evaluate the focused flake assertions and the Hades system:

```sh
nix build --no-link --no-update-lock-file .#checks.x86_64-linux.service-gateway
nix eval --raw --no-update-lock-file .#nixosConfigurations.hades.config.system.build.toplevel.drvPath
```

After deployment, verify the service, interface-scoped firewall, active route,
and streaming origin from a tailnet client:

```sh
sudo systemctl is-active tailscaled.service executor.service caddy.service
sudo nft list ruleset | grep -C3 -E 'tailscale0|dport (80|443)'
curl --fail --cacert ./root.crt https://executor.lab.xavierchanth.xyz/api/health
curl --fail --cacert ./root.crt -I https://executor.lab.xavierchanth.xyz/
sudo journalctl -u caddy.service --since today --no-pager
```

Confirm TCP 80 and TCP/UDP 443 are accepted only on `tailscale0`; the global
firewall remains closed for those ports. Then verify owner login and a harmless
read-only MCP call through the stable origin. The health path establishes
readiness, while the application checks establish authentication and protocol
correctness.

## Rollback

Roll back to the previous NixOS generation and confirm `caddy.service` plus the
previous application units are active. Gateway rollback does not change
Executor's durable state. If the route is intentionally removed, remove its DNS
record or stop advertising it at the same time so clients do not retain a dead
stable contract. Preserve `/var/lib/caddy` during ordinary rollback so the
internal CA identity and installed client trust remain valid.
