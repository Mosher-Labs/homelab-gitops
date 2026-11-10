# Runbook: Pi-hole DNS replies error budget burn (fast and medium)

| Field | Value |
| --- | --- |
| Rule IDs | `pihole_dns_replies_burn_fast`, `pihole_dns_replies_burn_medium` |
| Severity | page |
| Owner | Bennie Mosher |
| Last reviewed | 2026-11-09 by Bennie Mosher |

The fast and medium alerts share this runbook. The slow alert has its own short runbook:
[pihole_dns_replies_burn_slow.md](pihole_dns_replies_burn_slow.md).

## What this alert means

Too many of the real DNS queries Pi-hole answered got SERVFAIL or REFUSED, for the 99.9% SLO.

- Fast: 14.4x the allowed rate over 1h and 5m. About 8 bad replies in an average hour, and never fewer
  than 5, the minimum the alert needs.
- Medium: 6x over 6h and 30m. About 20 bad replies in 6 hours.

Fires when: the burn rate is over the threshold in both windows. See the
[SLO document](../slos/pihole-dns.md).

## Impact

Some names don't resolve for some devices, while others work. The probe alerts
([pihole_dns_burn.md](pihole_dns_burn.md)) can stay quiet, because `example.com` still resolves. If
both SLIs are burning, Pi-hole itself is the problem: start with that runbook.

## First checks (5 minutes)

1. Which bad replies, and how many? In Grafana Explore (Prometheus):

   ```promql
   sum by (query_reply) (sum_over_time(pihole_query_reply_1m{query_reply=~"SERVFAIL|REFUSED"}[30m]))
   ```

   SERVFAIL points at the upstream or DNSSEC. REFUSED points at rate limiting.

2. Which names and which devices? Open the Pi-hole query log, <http://pihole.mosher-labs.local/admin/queries>,
   and filter by reply type. One device, one domain, or everything? If check 1 shows REFUSED and it is
   one client, that client is probably rate limited: go to [Rate limited device](#rate-limited-device)
   and skip check 3. The other devices resolve fine, so the upstreams are not the cause.

   The query log UI is slow for this. To rank clients and names by bad replies over the last 6 hours
   (`reply_type` 7 is SERVFAIL and 8 is REFUSED):

   ```bash
   kubectl -n pihole exec deploy/pihole -- pihole-FTL sqlite3 /etc/pihole/pihole-FTL.db \
     "select client, domain, count(*) n from queries where reply_type in (7,8) \
      and timestamp > strftime('%s','now','-6 hours') group by client, domain order by n desc limit 10;"
   ```

   If the top client is on a network that should not use Pi-hole, go to
   [A network that should not use Pi-hole](#a-network-that-should-not-use-pi-hole).

3. Does the failing name resolve upstream? Replace `<name>` with a name from check 2:

   ```bash
   kubectl -n pihole exec deploy/pihole -- dig +time=2 @1.1.1.1 <name>
   kubectl -n pihole exec deploy/pihole -- dig +time=2 +cd @1.1.1.1 <name>
   ```

   `+cd` turns DNSSEC checking off. If only the `+cd` query works, the domain's DNSSEC is broken.

## Likely causes

| Cause | How to confirm | Go to |
| --- | --- | --- |
| A domain with broken DNSSEC (Pi-hole has `DNSSEC: "true"`) | Check 3: SERVFAIL without `+cd`, an answer with it | [Broken DNSSEC](#broken-dnssec) |
| Upstream failing for some names | Check 3 fails both ways, and `dig @1.0.0.1 <name>` from a laptop fails too | [Upstream failing](#upstream-failing) |
| A device sending more than 1,000 queries in 60 seconds | REFUSED in check 1, one client in check 2 | [Rate limited device](#rate-limited-device) |
| One device asking for a name that fails | Check 2: one client, one domain | [One noisy device](#one-noisy-device) |
| A network that should not use Pi-hole (for example the work VLAN) | Check 2: the top client is on that network's subnet. `getent hosts <ip>` shows its name | [A network that should not use Pi-hole](#a-network-that-should-not-use-pi-hole) |
| A recent change | `git log --since=1.day -- apps/pihole` in homelab-gitops | Revert the PR |

## Mitigations

### Broken DNSSEC

That domain's owner has to fix it. If a device the house needs depends on it, the quick fix is a
conditional forward or a local DNS record for that name in Pi-hole (Settings, Local DNS). Note it in
History.

Do not: turn off DNSSEC for the whole network to fix one domain.

### Upstream failing

If Cloudflare fails for these names and another resolver works (`dig @9.9.9.9 <name>` from a
laptop), change `DNS1` and `DNS2` in `apps/pihole/application.yaml` through a PR, and change them back
when Cloudflare recovers.

Verify: check 1 stops growing within a few minutes.

### Rate limited device

Pi-hole refuses a client that sends more than 1,000 queries in 60 seconds (`dns.rateLimit`). Find out
why the device is sending that many: a stuck app or a misconfigured device. Fix or unplug the device.
Raise the limit only if the traffic is legitimate.

### A network that should not use Pi-hole

A managed work laptop sent a failing reverse lookup every few minutes because its VLAN's DHCP handed out
Pi-hole as the DNS server. Set that network to automatic DNS in UniFi. The change does not reach a client until
it renews its lease (24 hours), so turn the client's network adapter off and on to speed it up.

Verify: the client's last query in Pi-hole stops advancing, and the alert clears about 30 minutes after the last
bad reply.

Also check what else that network can reach. A device that is meant to be isolated should not be able to ping
the main LAN.

### One noisy device

A single device retrying one failing name can burn the budget for everyone. If the name is junk
(telemetry, a dead service), block it so Pi-hole answers it locally. If it matters, treat it like
[Upstream failing](#upstream-failing).

## Escalation

There's no one else on call. If many names fail for every device, follow
[pihole_dns_burn.md](pihole_dns_burn.md), including its fallback to `1.1.1.1`.

## Dashboards, queries and logs

- SLO dashboard: <http://grafana.mosher-labs.local/d/slos-homelab/slos-homelab>
- Pi-hole dashboard: <http://grafana.mosher-labs.local/d/MIBVglomg/pi-hole-exporter>
- Bad replies per minute: `sum(pihole_query_reply_1m{query_reply=~"SERVFAIL|REFUSED"})`
- Queries per upstream: `pihole_query_upstream_1m`, and per client: `pihole_query_client_1m`
- Logs: `kubectl -n pihole exec deploy/pihole -- tail -n 200 /var/log/pihole/pihole.log`

## After the alert

- Was the alert noisy or not actionable? It needs at least 5 bad replies, so if it paged on one device
  and nothing else, note it for the next SLO review (2026-11-06).
- Did this runbook miss a step? Fix it now.
- Does this need a postmortem? Write one if it used a large part of the budget or surprised you. Use
  the [postmortem template](https://github.com/Mosher-Labs/terraform-kubernetes-observability/blob/main/docs/templates/postmortem.md).

## History

| Date | What happened | Link |
| --- | --- | --- |
| 2026-10-11 | SLI added, alerts failure-tested in Slack and Webex | [#204](https://github.com/Mosher-Labs/homelab-gitops/pull/204) |
| 2026-11-09 | First real firing (medium, burn rate 6.3). One work laptop sent a reverse lookup for `0.0.136.142.in-addr.arpa` about every 4 minutes, and the zone returns SERVFAIL from 1.1.1.1, 9.9.9.9, and with `+cd`. Its VLAN was set to use Pi-hole for DNS. Set it to automatic DNS in UniFi. 1,417 of the 1,676 bad replies in 30 days came from that one client and name | [#256](https://github.com/Mosher-Labs/homelab-gitops/issues/256) |
