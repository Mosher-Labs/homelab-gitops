# Error budget policy: homelab

| Field | Value |
| --- | --- |
| Service | Homelab services with an SLO (first: Pi-hole DNS) |
| SLO document | [pihole-dns.md](pihole-dns.md) |
| Authors | Bennie Mosher |
| Approvers | Bennie Mosher |
| Approved on | Not yet |
| Revisit on | 2026-12-08 |

## Goals

- Keep the services the household depends on working.
- Make it clear when to stop changing things and fix reliability.

## Non-goals

- Punishing myself for a missed SLO. A freeze is permission to put reliability first, not a penalty.
- Setting SLOs so tight that no change can ship.

## Scope

This policy covers changes to the cluster, to the service, and to its
configuration in homelab-gitops.

## When the budget is not spent

Changes proceed as normal.

## When the budget is spent

Evaluated over 30 days. A service has spent its budget when any one of its SLIs has. For Pi-hole, that is
either the probe SLI or the real-query SLI. Until the service is back within its SLO:

1. Stop non-urgent changes to the affected service and anything it depends on.
   Security fixes and fixes for the cause of the outage are allowed.
   Renovate pull requests count as changes: leave the ones for the affected service and its dependencies
   open and unmerged until the freeze ends, unless they are security updates. Renovate pull requests for
   unrelated services can still merge.
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

- One incident that uses more than 20% of the budget gets a short postmortem and at least one P0 issue.
  For Pi-hole, that is more than about 52 failed probes (8.6 minutes) on the probe SLI, or more than about
  90 bad replies on the real-query SLI.
- One kind of outage (for example, deploys) that uses more than 20% of the budget over a quarter puts a P0
  issue on the next quarter's plan.
- This applies even when the budget is not spent. One bad day can cross 20% without crossing 100%.

## Disagreements

I run this cluster alone, so I decide how the budget is calculated and what the policy requires. I write the
decision and the reason in the standup notes, and in the review log below if it changes the policy.

## Review

Review this policy monthly while the first SLO is new, then quarterly. The 2026-11-06 review date passed
without a review, so the next one is 2026-12-08.

| Date | Change | Who agreed |
| --- | --- | --- |
| 2026-10-06 | Initial draft | Bennie Mosher |
| 2026-11-08 | Added non-goals, disagreements, the either-SLI rule, Renovate pull requests as changes, the quarterly outage threshold, and thresholds in probes and replies. Moved the revisit date to 2026-12-08. | Not yet approved |
