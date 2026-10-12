# Runbook (short): Pi-hole DNS replies slow error budget burn

| Field | Value |
| --- | --- |
| Rule ID | `pihole_dns_replies_burn_slow` |
| Severity | ticket |
| Owner | Bennie Mosher |
| Last reviewed | 2026-10-11 |

## What it means

Real DNS queries have gotten SERVFAIL or REFUSED at 3x the allowed rate over the last day (and the last
2 hours). That's about 44 bad replies in a day. At this rate the 30-day budget is gone in 10 days.

## First thing to check

Run `sum by (query_reply) (sum_over_time(pihole_query_reply_1m{query_reply=~"SERVFAIL|REFUSED"}[1d]))`
in Grafana Explore, then filter the Pi-hole query log
(<http://pihole.mosher-labs.local/admin/queries>) by that reply type. One device or one domain is the
usual answer. The full runbook, [pihole_dns_replies_burn.md](pihole_dns_replies_burn.md), has the
causes.

## Who to tell

Bennie. It can wait for the next free evening. Open an issue on the Homelab & Platform board if the
cause needs work.
