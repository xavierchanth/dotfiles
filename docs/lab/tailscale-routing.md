# Tailscale routing on Hades

Hades is the Lab's single Tailscale routing identity. It retains the MagicDNS
hostname `hades`, uses `tag:lab-host`, hosts `svc:lab`, advertises the home LAN,
and offers exit-node service. These are capabilities of one tagged node, not
separate node or service identities.

The current tailnet suffix is `goat-roygbiv.ts.net`, so Hades's full MagicDNS
name is `hades.goat-roygbiv.ts.net`. MagicDNS and Tailscale HTTPS certificate
support are enabled. The routing rollout preserves both settings and names.

The live route was confirmed on Hades before configuration: `enp1s0` owns the
directly connected `192.168.8.0/24` LAN, Hades has the recovery address
`192.168.8.2`, and Eris is `192.168.8.202`. The advertised subnet is therefore
exactly `192.168.8.0/24`.

## Declarative host contract

The Hades configuration enables Tailscale's server routing features and applies
these preferences with `tailscale set`:

```text
--accept-dns=false
--accept-routes=false
--advertise-exit-node
--advertise-routes=192.168.8.0/24
--advertise-tags=tag:lab-host
--exit-node=
--exit-node-allow-lan-access=false
--ssh
```

`useRoutingFeatures = "server"` enables IPv4 and IPv6 forwarding. Hades neither
accepts other subnet routes nor selects an exit node for its own traffic. The
configuration deliberately leaves Tailscale's normal subnet-route SNAT enabled;
there is no `--snat-subnet-routes=false` flag. LAN devices therefore see routed
connections as originating from Hades, avoiding a second return-route
requirement on the home router.

## Tailnet policy contract

[`tailscale-policy-fragment.json`](tailscale-policy-fragment.json) is the exact
fragment to merge into the existing tailnet policy. It assigns `tag:lab-host`
to the tailnet owner and uses that tag to auto-approve the LAN route, exit-node
advertisement, and `svc:lab` advertisement. Grants permit the owner to:

- use Tailscale SSH to reach the local `chant` account on tagged Lab hosts;
- reach the home LAN through `tag:lab-host`;
- use the tagged Hades router for internet egress; and
- reach `svc:lab` on TCP 443.

Merge the fragment; do not replace unrelated existing policy. Policy must be
valid before Hades requests the tag and advertises routes. Auto-approvers apply
when an advertisement is first received; if a route was already pending before
the policy change, withdraw and re-advertise it or approve it explicitly.

Applying `tag:lab-host` changes Hades from a user-owned node to a tagged server
identity without changing its Tailscale IP address or MagicDNS machine name.
The `svc:lab` service remains its own stable Tailscale Service identity and is
authorized to use Hades as a backend through the service auto-approver.

## Attended rollout and acceptance

1. Merge and save the policy fragment. Use the policy editor's validation and
   confirm its policy tests pass.
2. Deploy Hades while an independent LAN or console recovery path is available.
3. Confirm `tailscale status --json` reports `tag:lab-host`, Hades's existing
   MagicDNS name, the `192.168.8.0/24` route, and exit-node availability.
4. Confirm the route and exit-node advertisement are approved. An existing
   unapproved advertisement may require a withdraw/re-advertise cycle because
   auto-approval is not retroactive.
5. From a tailnet client outside the home LAN, reach `192.168.8.2` and at least
   one non-Tailscale LAN device. Confirm that a LAN device observes Hades as the
   source, proving normal SNAT remains active.
6. Select Hades as the client exit node, confirm the public egress address is
   the home connection, then deselect it. Hades itself must still report no
   selected exit node and no accepted subnet routes.
7. Validate `hades` through MagicDNS, Tailscale SSH as `chant`, and `svc:lab`
   independently. The routing change does not rename either identity.

## DNS interaction and recommendation

The tailnet sends the entire `xavierchanth.xyz` split-DNS zone to Charon at
`192.168.8.1` and uses `xavierchanth.xyz` as a search domain. Preserve that
full-zone route. Charon is the private authority for these Lab answers:

- `charon.lab.xavierchanth.xyz` remains the explicit `192.168.8.1` answer;
- `lab.xavierchanth.xyz` resolves to the `svc:lab` TailVIP; and
- `*.lab.xavierchanth.xyz` resolves to the same `svc:lab` TailVIP.

The observed bare-zone override `xavierchanth.xyz -> 192.168.8.41` is not owned
by this repository, and live checks found no responding host at `.41`. Treat it
as stale or unexplained state: capture Charon's exact current configuration and
backup before removal, then let bare `xavierchanth.xyz` resolve through Charon's
ordinary upstream DNS. Do not replace it with `192.168.8.1`; using the domain
apex for the router UI requires a separate explicit Xavier decision.

The Lab origins are private-only. Do not publish public DNS records for the Lab
apex or wildcard, and do not add a public-resolver exception for the Lab
subdomain.

The cost is that every `xavierchanth.xyz` lookup from a tailnet client depends
on reaching `192.168.8.1`. Remote clients therefore need the Hades subnet route
for DNS as well as LAN access. A visited network using the same
`192.168.8.0/24` range can make both DNS and LAN destinations ambiguous.

The required rollout is:

1. Keep the existing `xavierchanth.xyz` restricted nameserver and search domain.
2. Back up Charon and record the source of the `.41` apex override, then remove
   only that override. Confirm bare `xavierchanth.xyz` matches ordinary upstream
   DNS while `charon.lab.xavierchanth.xyz` remains `192.168.8.1`. Restore the
   backup if unrelated resolution regresses.
3. Configure Charon with explicit private answers for both
   `lab.xavierchanth.xyz` and `*.lab.xavierchanth.xyz` using the recorded
   `svc:lab` TailVIP. The wildcard does not replace the `lab` record itself.
4. From an off-LAN tailnet client, prove the operating-system resolver reaches
   Charon through the Hades subnet route. Confirm the bare apex matches upstream,
   the explicit Charon record remains `.1`, and both Lab names resolve to the
   TailVIP.
5. Treat reachability of `192.168.8.1` and a non-overlapping client route as
   availability requirements. Do not bypass Charon with a public resolver.

Rollback restores the captured `.41` override exactly as it existed before
removal; it never synthesizes a new apex mapping. Restore it only when reverting
this cleanup, independently of the `svc:lab` records.

Test through the operating system resolver and a real HTTPS client; direct
`nslookup` queries can bypass platform split-DNS policy. Repeat with Hades
selected and deselected as the exit node, because exit-node DNS handling can
differ unless a nameserver is explicitly enabled for use with exit nodes.

Rollback is pre-exposure friendly: withdraw the route and exit-node
advertisement, then roll Hades back. Preserve the `tag:lab-host` and `svc:lab`
policy entries if the existing service gateway still uses them. Removing the
tag requires an intentional re-authentication back to a user-owned identity.

## Overlapping remote LANs

A client visiting another network that also uses `192.168.8.0/24` has two
different destinations represented by the same addresses. The operating system
may prefer the local route or the Tailscale route depending on platform and
route specificity, so an address such as `192.168.8.202` is ambiguous in that
location. Exit-node selection and MagicDNS names do not themselves collide.

The safe operational response is to avoid raw home-LAN addresses on an
overlapping network, use the target's Tailscale/MagicDNS identity when it has
one, or move one LAN to a non-overlapping CIDR. Tailscale 4via6 can disambiguate
multiple intentionally overlapping routed sites, but it is a separate design
and is not enabled by this change.

## References

- [Tailscale subnet routers](https://tailscale.com/docs/features/subnet-routers)
- [Tailscale exit nodes](https://tailscale.com/docs/features/exit-nodes)
- [Tailnet policy syntax](https://tailscale.com/docs/reference/syntax/policy-file)
- [Tailscale Services](https://tailscale.com/kb/1552/tailscale-services)
- [Overlapping LAN and subnet routes](https://tailscale.com/docs/reference/troubleshooting/network-configuration/lan-traffic-overlapping-subnets)
- [Tailscale CLI settings](https://tailscale.com/docs/reference/tailscale-cli)
- [DNS in Tailscale](https://tailscale.com/docs/reference/dns-in-tailscale)
