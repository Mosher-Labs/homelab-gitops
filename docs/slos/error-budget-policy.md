# Error budget policy: homelab

| Field | Value |
| --- | --- |
| Service | Homelab services with an SLO (first: Pi-hole DNS) |
| SLO document | [pihole-dns.md](pihole-dns.md) |
| Authors | Bennie Mosher |
| Approvers | Bennie Mosher |
| Approved on | Not yet |
| Revisit on | 2026-11-06 |

## Goals

- Keep the services the household depends on working.
- Make it clear when to stop changing things and fix reliability.

## Scope

This policy covers changes to the cluster, to the service, and to its
configuration in homelab-gitops.

## When the budget is not spent

Changes proceed as normal.

## When the budget is spent

Evaluated over 30 days. Until the service is back within its SLO:

1. Stop non-urgent changes to the affected service and anything it depends on.
   Security fixes and fixes for the cause of the outage are allowed.
2. Work on reliability items first. The list is the P0 and P1 issues on the
   Homelab & Platform board.
3. Write the cause and the fix in the standup notes.

## Exceptions

Changes can continue when the budget was spent mainly by:

- A power or internet outage.
- A measurement error with no effect on the household, such as a failing probe
  with DNS working for every device.

Stop changes when the cause was a deploy, a config change or a missing alert.

## Postmortem thresholds

- One incident that uses more than 20% of the budget (about 9 minutes of
  failed probes for the Pi-hole SLO) gets a short postmortem and at least one
  P0 issue.

## Review

Review this policy monthly while the first SLO is new, then quarterly.

| Date | Change | Who agreed |
| --- | --- | --- |
| 2026-10-06 | Initial draft | Bennie Mosher |
