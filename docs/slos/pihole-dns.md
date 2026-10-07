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
| Availability | Share of DNS probes that get a NOERROR answer for `example.com` | probes that succeeded / all probes | `probe_success{target="pihole-dns"}` from the blackbox exporter, one probe a minute | 99.9% |

A valid event is one probe. A good event is a probe that gets NOERROR within
the 5 second timeout. All probes count, so a missing probe is a failure.

## Rationale

99.9% is about 43 minutes of failed probes in 30 days. Every device on the
network depends on this service, and a short outage is already noticeable. The
number is an estimate. It has not been checked against how often the network
actually has problems.

The SLI is a synthetic probe, not the real queries. Pi-hole's own statistics
(`pihole_query_count`, `pihole_query_replies`) are gauges over a 24-hour
window, so the share of SERVFAIL and REFUSED replies reacts too slowly for
burn-rate windows. In the last 7 days there were no SERVFAIL or REFUSED replies.

## Error budget

Error budget = 100% minus the SLO. For 99.9% over 30 days, the budget is about
43 minutes, which is about 43 failed probes at one probe a minute.

What happens when the budget is spent: see the error budget policy.

## Alerting

| Alert | Burn rate | Long window | Short window | Action |
| --- | --- | --- | --- | --- |
| Fast burn | none | none | none | Not used |
| Medium burn | 6 | 6h | 30m | Page |
| Slow burn | 3 | 1d | 2h | Ticket |

The fast burn alert is left out. With a probe a minute, one failed probe in an
hour is a 1.7% error rate, a burn rate of 16.7, so a single blip would page.
The medium alert needs about 3 failed probes in 6 hours, which separates a
sustained problem from a blip.

Rules are rendered by `modules/slo` in `infrastructure/observability-alerts`
(`locals.tf`, `main.tf`). Runbook: [RUNBOOK.md](../../infrastructure/observability-alerts/RUNBOOK.md).

## Dependencies and caveats

- The probe runs inside the cluster, so a network problem outside it, such as
  the LoadBalancer address or the router, is not measured.
- The blackbox exporter itself failing counts as failed probes, because a
  missing `probe_success` series gives no data and the alert stays quiet. The
  existing scrape target down alerts cover that case.
- The probe asks for one name. A broken upstream for other names is not seen.

## Review log

| Date | Change | Who agreed |
| --- | --- | --- |
| 2026-10-06 | Initial draft | Bennie Mosher |
