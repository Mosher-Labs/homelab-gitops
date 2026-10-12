# Runbook: Pi-hole DNS error budget burn (fast and medium)

| Field | Value |
| --- | --- |
| Rule IDs | `pihole_dns_burn_fast`, `pihole_dns_burn_medium` |
| Severity | page |
| Owner | Bennie Mosher |
| Last reviewed | 2026-10-11 by Bennie Mosher |

The fast and medium alerts share this runbook. They watch the same probe and differ only in how fast
the budget is going. The slow alert has its own short runbook: [pihole_dns_burn_slow.md](pihole_dns_burn_slow.md).

## What this alert means

The blackbox exporter asks Pi-hole for `example.com` every 10 seconds, and too many of those probes are
failing for the 99.9% SLO.

- Fast: 14.4x the allowed rate over 1h and 5m. About 6 failed probes in an hour, or 1 minute of DNS down.
- Medium: 6x over 6h and 30m. About 13 failed probes in 6 hours.

Fires when: the burn rate is over the threshold in both windows. See the
[SLO document](../slos/pihole-dns.md).

## Impact

Every device on the home network uses Pi-hole (`192.168.87.101`) for DNS. If this is real, websites
and apps stop loading and cloud-connected smart home devices drop off. If only the probe is broken,
nobody notices.

## First checks (5 minutes)

1. Is DNS broken, or just the probe? From a machine on the LAN:

   ```bash
   dig +time=2 @192.168.87.101 example.com
   ```

   An answer with addresses means DNS works. Go to [Probe broken](#probe-broken-dns-fine).

2. Is Pi-hole running?

   ```bash
   kubectl -n pihole get pods -o wide
   kubectl -n pihole exec deploy/pihole -- pihole status
   ```

   Healthy: the `pihole` pod is `1/1 Running`, and FTL is listening on port 53.

3. Can Pi-hole reach its upstream (Cloudflare)?

   ```bash
   kubectl -n pihole exec deploy/pihole -- dig +short +time=2 @1.1.1.1 example.com
   ```

   Healthy: one or more addresses.

## Likely causes

| Cause | How to confirm | Go to |
| --- | --- | --- |
| Pi-hole pod down or restarting | Check 2. Look at RESTARTS, and `kubectl -n pihole describe pod -l app=pihole` | [Restart Pi-hole](#restart-pi-hole) |
| Its node is down | `kubectl get nodes` | [Node down](#node-down) |
| Upstream or internet down | Check 3 fails | [Upstream or internet down](#upstream-or-internet-down) |
| LoadBalancer IP missing | `kubectl -n pihole get svc pihole-dns-udp` doesn't show `192.168.87.101` | [MetalLB](#metallb) |
| Probe broken, DNS fine | Check 1 works | [Probe broken](#probe-broken-dns-fine) |
| A recent change | `git log --since=1.day -- apps/pihole infrastructure` in homelab-gitops | [Roll back](#roll-back) |

## Mitigations

### Restart Pi-hole

```bash
kubectl -n pihole rollout restart deploy/pihole
kubectl -n pihole rollout status deploy/pihole
```

Verify: check 1 answers, and `probe_success{target="pihole-dns"}` is back to 1 within a minute.

Do not: scale Pi-hole to more than one replica. Pi-hole v6 sessions break with several replicas (see
`apps/pihole/application.yaml`).

### Node down

Pi-hole has one replica and no PVC, so Kubernetes can move it to the other node. That only works while
the control plane is up, and the control plane runs on `hp-elitedesk`. If `hp-elitedesk` is down,
bring it back first.

Verify: the pod is `Running` on a `Ready` node, then check 1.

### Upstream or internet down

If check 3 fails for other addresses too (`dig @1.0.0.1`, `ping 1.1.1.1` from a laptop), the internet
connection is down. Nothing in the cluster will fix it. Check the router and the ISP. An internet
outage is an exception in the [error budget policy](../slos/error-budget-policy.md).

If only Cloudflare fails, change `DNS1` and `DNS2` in `apps/pihole/application.yaml` to another
resolver through a PR, and change them back afterwards.

### MetalLB

```bash
kubectl -n metallb-system get pods
kubectl -n metallb-system logs -l app.kubernetes.io/component=speaker --tail=50
```

Restart the speaker pods if they aren't `Running`. Verify: the service shows `192.168.87.101` and
check 1 answers.

### Probe broken, DNS fine

```bash
kubectl -n monitoring get pods | grep blackbox
```

Restart the blackbox exporter if it isn't `Running`. The budget burned while the probe was broken
wasn't real. Note it in the History table so the SLO review can account for it.

### Roll back

Revert the PR that caused it, and merge the revert. ArgoCD syncs on its own, but after a merge it has
taken more than 5 minutes to notice. Refresh the app in ArgoCD to speed that up.

## Escalation

There's no one else on call. If DNS isn't back in 15 minutes, point devices or the router's DNS
setting at `1.1.1.1` so the house has DNS. That drops ad-blocking until Pi-hole is back.

If the outage used a large part of the budget, follow the
[error budget policy](../slos/error-budget-policy.md).

## Dashboards, queries and logs

- SLO dashboard: <http://grafana.mosher-labs.local/d/slos-homelab/slos-homelab>
- Pi-hole dashboard: <http://grafana.mosher-labs.local/d/MIBVglomg/pi-hole-exporter>
- Probe: `probe_success{target="pihole-dns"}` and `probe_duration_seconds{target="pihole-dns"}`
- Error rate over the last hour: `1 - avg_over_time(probe_success{target="pihole-dns"}[1h])`
- Logs: `kubectl -n pihole logs deploy/pihole --since=1h`, or `{namespace="pihole"}` in Grafana Explore (Loki)

## After the alert

- Was the alert noisy or not actionable? Note it for the next SLO review (2026-11-06).
- Did this runbook miss a step? Fix it now.
- Does this need a postmortem? Write one if it used a large part of the budget or surprised you. Use
  the [postmortem template](https://github.com/Mosher-Labs/terraform-kubernetes-observability/blob/main/docs/templates/postmortem.md).

## History

| Date | What happened | Link |
| --- | --- | --- |
| 2026-10-09 | Probe moved to every 10 seconds and the fast alert turned on | [#201](https://github.com/Mosher-Labs/homelab-gitops/pull/201) |
