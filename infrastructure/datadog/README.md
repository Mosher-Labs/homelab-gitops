# datadog

The Datadog Agent, on Datadog's free trial, so we can see how Datadog alerts and
learn from it. The monitors come from `infrastructure/datadog-alerts`.

## What runs

- The Agent on every node, the Cluster Agent (which runs kube-state-metrics
  collection), and the Datadog Operator that the chart installs.
- No logs (Loki has them) and no APM (the OpenTelemetry collector has traces).
- Tagged `kube_cluster_name:homelab`, which the monitors match.

## Secrets

Both are SealedSecrets in `manifests/`:

- `datadog-secret`: the Datadog API key, from the 1Password item "datadog api
  key".
- `datadog-cluster-agent-token`: a random token the Cluster Agent and the Agents
  share. It stays fixed so the chart doesn't generate a new one on every render.

To reseal either, as in `infrastructure/sealed-secrets/README.md`:

```bash
kubectl create secret generic datadog-secret -n datadog \
  --from-literal=api-key="$(op item get 'datadog api key' --vault 'Mosher Home' --fields credential --reveal)" \
  --dry-run=client -o yaml |
  kubeseal --controller-namespace kube-system --format yaml \
    > manifests/api-key-sealed-secret.yaml
```

## The trial

Datadog's trial is 14 days and needs no credit card. We don't add one. After it
ends, Datadog moves the org to its free plan. Check what that plan includes
before relying on it. To remove Datadog, delete this directory and
`infrastructure/datadog-alerts`, and ArgoCD removes the Agent.
