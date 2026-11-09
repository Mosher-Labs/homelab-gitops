# Postmortem: Work VLAN laptop spent the Pi-hole error budget

| Field | Value |
| --- | --- |
| Date of incident | 2026-10-25 to 2026-11-09 |
| Authors | Bennie Mosher |
| Status | draft |
| Severity | Low user impact, SLO breached |
| Incident document | [#256](https://github.com/Mosher-Labs/homelab-gitops/issues/256) |
| Reviewed on | Not yet |

## Summary

One work laptop on a VLAN that used Pi-hole for DNS sent a reverse lookup that fails everywhere, about every
4 minutes, for about 15 days. Those lookups were 85% of the bad replies in the 30-day window and put the Pi-hole
replies SLO at 219% of its error budget. I fixed it by setting the VLAN to automatic DNS in UniFi on 2026-11-09.

## Impact

- Duration: about 2026-10-25 to 2026-11-09 13:40 UTC (about 15 days). The laptop first appears in Pi-hole on
  2026-10-25 14:07 UTC.
- Systems affected: the Pi-hole replies SLI. Only one client sent the failing lookup. No user-visible failure is
  known. The lookup looks like a background Bonjour domain check, but I have not confirmed that on the laptop.
- Bad replies: 1,676 SERVFAIL or REFUSED in 30 days, out of 766,817 replies. 1,417 came from that one client and
  one name (`0.0.136.142.in-addr.arpa`).
- Error budget consumed: about 219% of the 30-day budget (budget is about 767 bad replies at 99.9%). Without the
  one client, about 259 bad replies, or about 34%.

## Timeline

All times in UTC.

| Time | Event |
| --- | --- |
| 2026-10-25 | A UniFi DHCP DNS change on a VLAN is recorded in my learnings that day. I think this pointed the work VLAN at Pi-hole. I still need to confirm which VLAN it was. |
| 2026-10-25 14:07 | The laptop's first query reaches Pi-hole. |
| 2026-10-26 | 179 bad replies in one day, 159 from the laptop. |
| 2026-11-07 | By replaying the rule, the medium burn condition was true for about 105 minutes. |
| 2026-11-08 | By replaying the rule, the medium burn condition was true for about 23.7 hours (burn rate up to 11). |
| 2026-11-09 13:18 | Slack: "Pi-hole DNS replies: medium error budget burn" fires (burn rate 6.3). |
| 2026-11-09 13:2x | Runbook checks find one client and one name behind 19 of 21 recent bad replies. |
| 2026-11-09 about 13:40 | VLAN set to automatic DNS in UniFi, and the laptop's network adapter turned off and on. I do not have exact times for these. |
| 2026-11-09 13:40:45 | Last query from the laptop reaches Pi-hole. |

## Root causes

1. The failing lookup's reverse zone returns SERVFAIL from 1.1.1.1, from 9.9.9.9, and with DNSSEC checking off.
   Nothing on the homelab side can fix it.
2. The work VLAN's DHCP handed out Pi-hole as its DNS server, so a managed work laptop sent its lookups to
   the homelab.
3. Before the change, a ping from the main LAN to the laptop succeeded, and Pi-hole saw its real address. That
   suggests the VLAN can reach the main LAN. I have not checked the firewall rules.
4. The SLI counts a failed lookup from any client the same, including lookups no one in the house depends on.
5. The medium burn condition was true on 2026-11-07 and 2026-11-08, and I have no record of a notification before
   2026-11-09. I do not know why yet (see action items).

## Trigger

A change to DHCP DNS on the work VLAN, probably on 2026-10-25. To be confirmed.

## Resolution

Set the VLAN to automatic DNS in UniFi and renewed the laptop's lease. Pi-hole stopped receiving queries from it
within about 10 minutes. The permanent fixes are the action items below.

## Detection

The medium burn alert fired on 2026-11-09 13:18 UTC. By the rule's own math, it could have fired on
2026-11-07, which is about 2 days earlier. About 15 days passed between the trigger and detection. The probe SLI
stayed quiet the whole time, as the runbook predicts, because `example.com` kept resolving.

## Action items

| Action | Type | Priority | Owner | Tracking | Due |
| --- | --- | --- | --- | --- | --- |
| Find out why the medium burn condition on 2026-11-07 and 2026-11-08 did not reach Slack: check the Grafana alert state history, contact point, and notification policy | detect | P0 | Bennie Mosher | #256 | 2026-11-12 |
| Check that the work VLAN cannot reach the main LAN or the cluster, other than what it needs, and fix the firewall policy if it can | prevent | P0 | Bennie Mosher | To open | 2026-11-16 |
| Confirm which VLAN changed on 2026-10-25 and why Pi-hole was set as its DNS | process | P1 | Bennie Mosher | #256 | 2026-11-12 |
| Add the client-ranking query and the work VLAN cause to the runbook | process | P1 | Bennie Mosher | [#257](https://github.com/Mosher-Labs/homelab-gitops/pull/257) | 2026-11-09 |
| Decide whether the SLI should count failed lookups from every client, and record the decision in the SLO document | prevent | P2 | Bennie Mosher | To open | 2026-12-08 |
| Answer `vaww.va.gov` locally with NXDOMAIN, so the Citrix probe from `bennies-mbp` (about 10 bad replies a day) stops spending budget | mitigate | P2 | Bennie Mosher | [#259](https://github.com/Mosher-Labs/homelab-gitops/pull/259) | 2026-11-12 |

## Lessons learned

### What went well

- The runbook's first checks found one client and one name in a few minutes.
- The Prometheus SLI and Pi-hole's own database agree on the counts, so the numbers can be trusted.
- The probe SLI stayed quiet while the replies SLI burned, which is the split the second SLI was added to catch.

### What went badly

- The budget was overspent for about two weeks before I looked at it.
- The burn alert may have been true for two days before the first Slack message. I have not found out why.
- I had assumed the work VLAN was isolated from the homelab, and I had not tested that.
- The budget numbers in the policy assumed 15,000 queries a day. The real total is about 25,000, mostly from this
  one client.

### Where we got lucky

- The failing lookup was a background check, and no one reported a problem.
- Only one name caused almost all of the damage, which made the cause easy to find.

## Supporting information

- Runbook: [pihole_dns_replies_burn.md](../runbooks/pihole_dns_replies_burn.md)
- SLO document: [pihole-dns.md](../slos/pihole-dns.md)
- Query used to rank clients: in check 2 of the runbook
- Policy: [error-budget-policy.md](../slos/error-budget-policy.md)
