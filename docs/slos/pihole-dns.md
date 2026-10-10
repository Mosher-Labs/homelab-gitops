# SLO: Pi-hole DNS

| Field | Value |
| --- | --- |
| Service | Pi-hole DNS (`pihole-dns-udp.pihole.svc.cluster.local:53`, LoadBalancer `192.168.87.101`) |
| Status | Draft |
| Authors | Bennie Mosher |
| Reviewers | Bennie Mosher |
| Approvers | Bennie Mosher |
| Approved on | Not yet |
| Revisit on | 2026-11-06 |
| Error budget policy | [error-budget-policy.md](error-budget-policy.md) |

## Service overview

Pi-hole answers DNS for the home network and blocks listed domains. It handles
about 15,000 queries a day (14,540 on 2026-10-10). Everything on the network depends on it.

## Measurement window

Rolling 30 days.

## SLIs and SLOs

| Category | SLI (what we measure) | How it is calculated | Data source | SLO |
| --- | --- | --- | --- | --- |
| Availability (probe) | Share of DNS probes that get a NOERROR answer for `example.com` | probes that succeeded / all probes | `probe_success{target="pihole-dns"}` from the blackbox exporter, one probe every 10 seconds | 99.9% |
| Availability (real queries) | Share of real DNS replies that are not SERVFAIL or REFUSED | 1 - (SERVFAIL and REFUSED replies / all replies) | `pihole_query_reply_1m` from [pihole6-exporter](https://github.com/Mosher-Labs/pihole6-exporter) | 99.9% |

For the probe SLI, a valid event is one probe. A good event is a probe that gets
NOERROR within the 5 second timeout. All probes count, so a missing probe is a
failure.

For the real-query SLI, a valid event is one reply Pi-hole logged. A bad event
is a SERVFAIL or REFUSED reply. NXDOMAIN and NODATA are correct answers, so they
count as good. `UNKNOWN` replies count as good too: they include queries still
waiting on an upstream when the exporter reads the minute, so they are not all
failures (159 out of about 92,000 replies in the 7 days to 2026-10-10).

## Rationale

99.9% is about 43 minutes of failed probes in 30 days. Every device on the
network depends on this service, and a short outage is already noticeable. The
number is an estimate. It has not been checked against how often the network
actually has problems.

The probe alone is synthetic traffic, and the Workbook warns that successful
artificial requests can hide a failure real users see. For DNS, that looks like
one upstream resolver failing for some domains while `example.com` still
resolves. The real-query SLI covers that case.

It uses `pihole_query_reply_1m`, a count of replies by type for the last whole
minute. Pi-hole's other statistics (`pihole_query_count`,
`pihole_query_replies`) cover a 24-hour window and react too slowly for
burn-rate windows. The exporter stamps each sample with the minute it covers,
so the second 30-second scrape in a minute is a duplicate that Prometheus
drops, and `sum_over_time` counts each query once. On 2026-10-10 the 1-day sum
was 14,521 replies against Pi-hole's own 24-hour count of 14,540.

In the 7 days to 2026-10-10 there were no SERVFAIL or REFUSED replies. Those
series only exist after one happens, so the expression uses `or vector(0)` to
return 0 instead of no data.

## Error budget

Error budget = 100% minus the SLO. For 99.9% over 30 days, the budget is about
43 minutes, which is about 259 failed probes at one probe every 10 seconds.
For the real-query SLI it is 0.1% of replies, about 435 bad replies in 30 days
at 15,000 queries a day.

What happens when the budget is spent: see the [error budget policy](error-budget-policy.md).

## Alerting

| Alert | Burn rate | Long window | Short window | Action |
| --- | --- | --- | --- | --- |
| Fast burn | 14.4 | 1h | 5m | Page |
| Medium burn | 6 | 6h | 30m | Page |
| Slow burn | 3 | 1d | 2h | Ticket |

The probe runs every 10 seconds, which is 360 samples an hour. That is why the fast alert can stay on: at
one probe a minute, a single failed probe in an hour would be a 1.7% error rate, a burn rate of 16.7, and a
blip would page. At 10 seconds, the long window of each alert needs about:

| Alert | Failed probes in the long window | Roughly |
| --- | --- | --- |
| Fast burn | 6 in an hour | 1 minute of DNS down |
| Medium burn | 13 in 6 hours | 2 minutes |
| Slow burn | 26 in a day | 4 minutes |

The real-query SLI has the same three alerts. Traffic varies a lot, from 140 to
8,170 queries an hour (about 540 on average, week to 2026-10-10), so the number
of bad replies it takes changes with the hour:

| Alert | Bad replies in the long window |
| --- | --- |
| Fast burn | 8 in an average hour, 3 in the quietest hour |
| Medium burn | about 20 in 6 hours |
| Slow burn | about 44 in a day |

Three bad replies at night pages. That is on purpose for now, since there were
none in the last week, but revisit it if night pages turn out to be noise.

Rules are rendered by `modules/slo` in `infrastructure/observability-alerts`
(`locals.tf`, `main.tf`). Runbook: [RUNBOOK.md](../../infrastructure/observability-alerts/RUNBOOK.md).

## Dependencies and caveats

- The probe runs inside the cluster, so a network problem outside it, such as
  the LoadBalancer address or the router, is not measured.
- If the blackbox exporter itself fails, `probe_success` has no data and these
  alerts stay quiet. The [`scrape_target_down` alert](https://github.com/Mosher-Labs/terraform-kubernetes-observability/blob/v0.16.0/modules/catalog/catalog.tf)
  in the module's catalog covers that case.
- There is no Datadog side yet: the probe metric is not in Datadog. See
  [homelab-gitops#196](https://github.com/Mosher-Labs/homelab-gitops/issues/196).
- The probe asks for one name. A broken upstream for other names is not seen.
- The probe is synthetic traffic. A successful probe can hide a failure that real clients see, such as one
  upstream resolver timing out for some domains. The real-query SLI covers that
  ([homelab-gitops#203](https://github.com/Mosher-Labs/homelab-gitops/issues/203)).
- The real-query SLI only sees queries that reach Pi-hole. If Pi-hole is down, there are no replies to count,
  and the probe SLI is what alerts.
- If the exporter stops, the real-query SLI has no data and its alerts stay quiet. `scrape_target_down` covers
  that, as it does for the blackbox exporter.

## Review log

| Date | Change | Who agreed |
| --- | --- | --- |
| 2026-10-06 | Initial draft | Bennie Mosher |
| 2026-10-09 | Probe every 10 seconds, fast alert on (#201) | Bennie Mosher |
| 2026-10-10 | Second SLI from real query replies (#203) | Bennie Mosher |
