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
about 30,000 queries a day. Everything on the network depends on it.

## Measurement window

Rolling 30 days.

## SLIs and SLOs

| Category | SLI (what we measure) | How it is calculated | Data source | SLO |
| --- | --- | --- | --- | --- |
| Availability | Share of DNS probes that get a NOERROR answer for `example.com` | probes that succeeded / all probes | `probe_success{target="pihole-dns"}` from the blackbox exporter, one probe every 10 seconds | 99.9% |

A valid event is one probe. A good event is a probe that gets NOERROR within
the 5 second timeout. All probes count, so a missing probe is a failure.

## Rationale

99.9% is about 43 minutes of failed probes in 30 days. Every device on the
network depends on this service, and a short outage is already noticeable. The
number is an estimate. It has not been checked against how often the network
actually has problems.

The SLI is a synthetic probe, not the real queries. Pi-hole's own statistics
(`pihole_query_count` and `pihole_query_replies`, from
[pihole6-exporter](https://github.com/Mosher-Labs/pihole6-exporter)) are gauges
over a 24-hour window, so the share of SERVFAIL and REFUSED replies reacts too
slowly for burn-rate windows. In the last 7 days there were no SERVFAIL or
REFUSED replies.

## Error budget

Error budget = 100% minus the SLO. For 99.9% over 30 days, the budget is about
43 minutes, which is about 259 failed probes at one probe every 10 seconds.

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
  upstream resolver timing out for some domains. A second SLI from the real queries is tracked in
  [homelab-gitops#200](https://github.com/Mosher-Labs/homelab-gitops/issues/200).

## Review log

| Date | Change | Who agreed |
| --- | --- | --- |
| 2026-10-06 | Initial draft | Bennie Mosher |
