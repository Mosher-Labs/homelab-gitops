# Runbook (short): Pi-hole DNS slow error budget burn

| Field | Value |
| --- | --- |
| Rule ID | `pihole_dns_burn_slow` |
| Severity | ticket |
| Owner | Bennie Mosher |
| Last reviewed | 2026-10-11 |

## What it means

The DNS probe has failed at 3x the allowed rate over the last day (and the last 2 hours). That's about
26 failed probes in a day, or 4 minutes of DNS down in total, likely in short blips. At this rate the
30-day budget is gone in 10 days.

## First thing to check

Look at `probe_success{target="pihole-dns"}` for the last day on the
[SLO dashboard](http://grafana.mosher-labs.local/d/slos-homelab/slos-homelab), and line the dips up
with Pi-hole restarts (`kubectl -n pihole get pods`) and node events. If a cause stands out, use the
full runbook, [pihole_dns_burn.md](pihole_dns_burn.md).

## Who to tell

Bennie. It can wait for the next free evening. Open an issue on the Homelab & Platform board if the
cause needs work.
