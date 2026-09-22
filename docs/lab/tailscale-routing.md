# Tailscale routing and gateway DNS

Hades provides two independent capabilities: optional subnet/exit routing and
the tailnet-native private gateway. Gateway DNS and HTTPS do not use the
`192.168.8.0/24` subnet route, so they continue working on overlapping LANs and
when clients decline subnet routes.

## Tailnet DNS

During one-time admin-console setup, configure Hades's current Tailscale IPv4
address as the restricted nameserver for `xavierchanth.xyz`. If Hades is
recreated or re-enrolled with a different address, update that setting manually.
The address remains operational control-plane state rather than a canonical
hostname or repository constant.

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

Tailnet policy and authentication remain manual operator-managed Tailscale
settings for this personal lab. Sign Hades in normally, apply `tag:lab-host`,
retain the existing SSH, subnet-route, and exit-node rules, let the tag advertise
`svc:lab`, auto-approve that Service, and grant the owner TCP 443 access. The
repository does not validate or apply policy. OAuth or automated tailnet-wide
mutation requires explicit approval for a specific recurring need.

After the one-time Service definition and tagged-node authentication,
`svc-lab.service` applies the complete raw-TCP config only after Caddy is healthy,
advertises the Service, and derives the node address and TailVIP from live
Tailscale state. Its five-minute reconciliation timer atomically refreshes the
root-owned DNS receipt after restarts or address changes. Configure the
`xavierchanth.xyz` restricted nameserver once in the Tailscale admin console,
pointing it to Hades's current TailIP and enabling exit-node use if desired.
Recreating or re-enrolling Hades with a different TailIP requires updating that
entry manually. Verify this path from a tailnet client during attended rollout;
local recurring status does not query or mutate the Tailscale control plane.
Repository configuration never contains an assigned address, tailnet suffix, or
credential.

## Validation

- Resolve every explicit private name using the operating-system resolver.
- Resolve public MX, TXT/SPF, NS, and CAA records and compare them with public
  authoritative DNS.
- Disable subnet-route acceptance and test DNS plus HTTPS.
- Repeat from an overlapping `192.168.8.0/24` LAN.
- Select and deselect the exit node and repeat.
- Verify UDP/TCP 53 is reachable through Tailscale and unavailable through LAN
  or WAN interfaces.
- Run `sudo tailscale-service-gateway drain` and confirm HTTPS fails without a
  LAN fallback.
- Remove runtime Service state and confirm the resolver fails closed.

Rollback removes the restricted nameserver, runs the packaged drain command,
and rolls Hades back. Subnet and exit-node routing can be rolled back
independently.
