# Tailscale routing and gateway DNS

Hades provides two independent capabilities: optional subnet/exit routing and
the tailnet-native private gateway. Gateway DNS and HTTPS do not use the
`192.168.8.0/24` subnet route, so they continue working on overlapping LANs and
when clients decline subnet routes.

## Tailnet DNS

In the Tailscale DNS console, add Hades's live Tailscale node IPv4 address as a
restricted nameserver for `xavierchanth.xyz` and enable it for exit-node use.
The address is operational control-plane state, not a canonical hostname or a
repository constant.

The Hades resolver explicitly maps these names to the current `svc:lab`
Service address:

- `xavierchanth.xyz`
- `lab.xavierchanth.xyz`
- `executor.lab.xavierchanth.xyz`
- `cliproxyapi.lab.xavierchanth.xyz`
- `cpamp.lab.xavierchanth.xyz`

It forwards other queries to public resolvers. No wildcard is used. Machine
names and unknown nested services are therefore not silently converted into
gateway traffic.

## Policy and Service

Merge [`tailscale-policy-fragment.json`](tailscale-policy-fragment.json) into
the existing policy. It grants owner access to `svc:lab` on TCP 443 and retains
the existing SSH, subnet-route, and exit-node grants. Define `svc:lab` in the
admin console, approve Hades, and apply Hades's generated raw-TCP Service
configuration only after Caddy is healthy on `127.0.0.1:8443`.

The DNS console nameserver value and Service address must be copied from live
Tailscale state into Hades's root-owned runtime files. Changing or recreating
Hades requires an attended DNS-console update. Changing the Service address
requires re-verification and a resolver restart. Repository configuration never
contains either assigned address or the tailnet suffix.

## Validation

- Resolve every explicit private name using the operating-system resolver.
- Resolve public MX, TXT/SPF, NS, and CAA records and compare them with public
  authoritative DNS.
- Disable subnet-route acceptance and test DNS plus HTTPS.
- Repeat from an overlapping `192.168.8.0/24` LAN.
- Select and deselect the exit node and repeat.
- Verify UDP/TCP 53 is reachable through Tailscale and unavailable through LAN
  or WAN interfaces.
- Drain `svc:lab` and confirm HTTPS fails without a LAN fallback.
- Remove runtime Service state and confirm the resolver fails closed.

Rollback removes the restricted nameserver, drains the Service, and rolls Hades
back. Subnet and exit-node routing can be rolled back independently.
