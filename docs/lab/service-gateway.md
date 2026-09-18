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
`dotfiles.serviceGateway.tailscaleService.configFile`. Applying and approving it
is an attended operation.

## Runtime DNS state

The Hades resolver reads one root-owned, mode-`0600`, single-line state receipt:

```text
/var/lib/tailnet-gateway-dns/svc-lab-state.json
```

It records `service: "svc:lab"`, the resolver address, current Service address,
expiry, and prepared-state identity. The resolver rejects symlinks, insecure
ownership or permissions, malformed or expired receipts, and resolver-address
mismatches with `tailscale ip -4`. It synthesizes only the approved gateway names and
forwards everything else to public recursive DNS. There is no wildcard, so
unknown nested service names follow the empty public web DNS and fail closed.

CoreDNS binds TCP and UDP 53 to the live Tailscale address. The firewall admits
53 only on `tailscale0`. Forwarders are fixed public resolvers, preventing a
loop through Tailscale split DNS.

## Attended rollout

1. Define `svc:lab` with raw TCP 443 and approve tagged Hades as its host.
2. Merge the repository policy fragment.
3. Obtain the live Hades node address and Service address from the Tailscale
   admin console and verify both independently.
4. Create the single `svc-lab-state.json` receipt above with mode `0600`, the
   verified addresses, `service: "svc:lab"`, an expiry, and the prepared-state
   identity.
5. Configure Hades's live node address as the restricted nameserver for
   `xavierchanth.xyz`, including exit-node use.
6. Deploy with `nix run path:.#deploy -- hades`.
7. Export and authenticate Caddy's public root with
   `service-gateway-ca-export`; install that root on intended clients.

Do not add public A, AAAA, or CNAME records for these private origins. Preserve
public mail, TXT/SPF, NS, CAA, and other non-web records.

## Acceptance and rollback

With subnet routes disabled, test every origin through the operating-system
resolver from a remote tailnet client and from a network overlapping
`192.168.8.0/24`. Confirm public MX/TXT/NS answers match public DNS, the apex
redirect preserves path and query, and unknown service names fail.

Drain `svc:lab` to test HTTPS failure. Move either runtime state file aside and
restart the resolver to test fail-closed DNS. Rollback removes the restricted
nameserver, drains the Service, and restores the prior Hades generation; Caddy
CA state under `/var/lib/caddy` is preserved.
