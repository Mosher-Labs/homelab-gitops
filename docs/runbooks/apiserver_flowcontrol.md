# Runbook: API server priority queue backed up / rejecting requests

| Field | Value |
| --- | --- |
| Rule IDs | `apiserver_priority_queue_backed_up`, `apiserver_requests_rejected` |
| Severity | warning (queued), critical (rejected) |
| Owner | Bennie Mosher |
| Last reviewed | 2026-10-24 by Bennie Mosher |

Both alerts watch the API server's API Priority & Fairness (APF) queues and share this runbook.
Queueing means requests are being delayed; rejection means they are being dropped.

## What this alert means

The API server sorts incoming requests into priority levels and queues each one separately. A queue
that stays non-zero means more requests are arriving for that level than the server will dispatch,
so some client is being starved of API throughput.

- `apiserver_priority_queue_backed_up`: `apiserver_flowcontrol_current_inqueue_requests` above 0 for
  10 minutes. A brief spike is normal and will not fire.
- `apiserver_requests_rejected`: `apiserver_flowcontrol_rejected_requests_total` increased in the
  last 10 minutes. The counter is only created once something has been rejected, so this is silent
  until it matters.

## Impact

This is not only an "API is slow" alert. The kubelet renews node leases and writes pod status through
the same API server. Starve it and the symptoms show up far from the cause:

- Nodes flap `NodeNotReady` while their containers stay healthy.
- Pods sit at `Ready=False` with `ContainersReady=True`, because their status is stale.
- Services lose their endpoints, because the endpoints controller cannot keep up.
- Anything depending on those services breaks, including DNS.

That is exactly what happened on 2026-10-22. See
[Why it broke](https://github.com/Mosher-Labs/homelab-gitops/pull/224) for the full chain.

## First checks (5 minutes)

Find which priority level and which flow schema:

```bash
kubectl get --raw /metrics | grep '^apiserver_flowcontrol_current_inqueue_requests' | awk '$2>0'
kubectl get --raw /metrics | grep '^apiserver_flowcontrol_rejected_requests_total'
```

`flow_schema="service-accounts"` with `priority_level="workload-low"` means an in-cluster workload is
the source, not a human with kubectl.

Then find what is actually calling. Look for a resource and verb with an implausible count:

```bash
kubectl get --raw /metrics | grep '^apiserver_request_total' | sort -t' ' -k2 -gr | head -20
```

A count in the millions on `pods/log`, `pods/exec`, or an unscoped `LIST`/`WATCH` is the usual
culprit. Measure the live rate before blaming anything:

```bash
# sample the suspect counter twice, 60s apart, and divide
```

## Common causes

| Symptom | Cause | Fix |
| --- | --- | --- |
| Millions of `pods/log` CONNECT | A log collector reading through the API instead of off disk | Switch it to file tailing; see PR #224 |
| Millions of unscoped `pods` LIST/WATCH | A DaemonSet watching every pod on every node | Add a `spec.nodeName` field selector |
| `pods/exec` climbing | Exec-based probes or a shell-looping sidecar | Move to HTTP probes |
| Rejections only during a sync | Controller thundering herd | Usually self-resolving; check the controller's rate limits |

## Fix

Stop the offending client first; tuning APF is almost never the right answer. Scaling the workload to
zero buys time:

```bash
kubectl -n <namespace> scale deployment/<name> --replicas=0
```

Then fix the access pattern in Git so ArgoCD does not restore it. Note that any app with
`selfHeal: true` will undo a manual scale on its next sync, so land the Git change promptly.

## Verify recovery

```bash
# queue should return to 0 and stay there
kubectl get --raw /metrics | grep '^apiserver_flowcontrol_current_inqueue_requests' | awk '$2>0'
```

Then confirm the downstream damage cleared: no pods stuck `Ready=False`, and no services without
endpoints.

```bash
kubectl get pods -A | grep -v Running
kubectl get endpoints -A | awk '$2==""'
```

## Escalation

There is nobody to escalate to. If the source is not obvious within 30 minutes, scale down the most
likely in-cluster client to restore control-plane headroom, then diagnose with the pressure off.
