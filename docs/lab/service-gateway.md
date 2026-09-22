# Tailnet service gateway

Hades hosts the private gateway without depending on the home subnet route.
Tailnet clients resolve explicit private names to the runtime address assigned
to `svc:lab`; that Service forwards raw TCP 443 to Caddy on
`127.0.0.1:8443`. Assigned Tailscale addresses and the tailnet suffix remain
machine-local state rather than repository identities.

| Origin | Upstream | Behavior |
| --- | --- | --- |
| `https://xavierchanth.xyz` | — | 308 to `https://lab.xavierchanth.xyz`, preserving URI |
| `https://lab.xavierchanth.xyz` | `127.0.0.1:3000` | Homepage |
| `https://executor.lab.xavierchanth.xyz` | `127.0.0.1:4788` | Executor |
| `https://cliproxyapi.lab.xavierchanth.xyz` | `127.0.0.1:8317` | Approved inference paths only |
| `https://cpamp.lab.xavierchanth.xyz` | `127.0.0.1:18317` | CPA Manager Plus |

Caddy retains strict SNI, named virtual hosts, HTTP/1.1 and HTTP/2 only, health
checks, and its internal CA. CLIProxyAPI permits only `/v1/models`,
`/v1/responses`, and `/v1/responses/compact`. Unknown names and paths fail
closed. Host TCP 80, TCP 443, and UDP 443 remain closed because Tailscale
Services supplies the transport.

The generated Service configuration is available through
`dotfiles.serviceGateway.tailscaleService.configFile`. `svc-lab.service` applies
that complete config, advertises `svc:lab`, waits for an approved TailVIP route,
and derives the DNS receipt from authenticated local Tailscale state. A timer
reconciles the same desired state every five minutes after restarts,
re-addressing, TailVIP rotation, and NixOS redeployment.

## Runtime DNS state

The Hades resolver reads one root-owned, mode-`0600`, single-line state receipt:

```text
/var/lib/tailnet-gateway-dns/svc-lab-state.json
```

It records `service: "svc:lab"`, the resolver address, current Service address,
expiry, stable node identity, and the desired Service-config digest. The
reconciler replaces it atomically only after the live config, advertisement,
approval, endpoint, Caddy health, node address, and TailVIP agree. The resolver
rejects symlinks, insecure ownership or permissions, malformed or expired
receipts, and resolver-address mismatches with `tailscale ip -4`. It synthesizes
only the approved gateway names and forwards everything else to public recursive
DNS. There is no wildcard, so unknown nested service names follow the empty
public web DNS and fail closed.

CoreDNS binds TCP and UDP 53 to the live Tailscale address. The firewall admits
53 only on `tailscale0`. Forwarders are fixed public resolvers, preventing a
loop through Tailscale split DNS.

## One-time bootstrap

1. Manually sign Hades into Tailscale using the normal interactive node login,
   apply `tag:lab-host`, and define/approve `svc:lab` with TCP 443. In the
   existing tailnet policy, let that tag advertise the Service, auto-approve it,
   and grant the owner TCP 443 access.
2. In the Tailscale admin console, manually add a restricted nameserver for
   `xavierchanth.xyz` pointing to Hades's current Tailscale IPv4 address. Enable
   use with an exit node if desired. If Hades is recreated or re-enrolled with a
   different TailIP, update this entry manually.
3. Deploy with `nix run path:.#deploy -- hades`.
4. Export and authenticate Caddy's public root with
   `service-gateway-ca-export`; install that root on intended clients.

Prefer normal interactive sign-in and manual admin-console changes for
tailnet-wide tags, Service approval, restricted DNS, and access policy. Nix owns
only Hades's local Tailscale client and advertised `svc:lab` state. OAuth or
automated tailnet-wide mutation requires explicit approval for a specific
recurring need.

Normal deployment performs no recurring `tailscale serve` or receipt-writing
steps by hand. It does not mutate restricted-DNS settings. Check convergence
with `sudo tailscale-service-gateway status`
or its `--json` form. Use `sudo tailscale-service-gateway drain` for an explicit,
idempotent withdrawal; it preserves Caddy state and the desired Nix config while
stopping private DNS. `sudo tailscale-service-gateway apply` restores the host.

Do not add public A, AAAA, or CNAME records for these private origins. Preserve
public mail, TXT/SPF, NS, CAA, and other non-web records.

## Acceptance and rollback

With subnet routes disabled, test every origin through the operating-system
resolver from a remote tailnet client and from a network overlapping
`192.168.8.0/24`. Confirm public MX/TXT/NS answers match public DNS, the apex
redirect preserves path and query, and unknown service names fail.

Run the packaged drain command to test HTTPS failure. Move the runtime receipt
aside and restart the resolver to test fail-closed DNS. Rollback removes the
restricted nameserver, drains the Service, and restores the prior Hades
generation; Caddy CA state under `/var/lib/caddy` is preserved.
