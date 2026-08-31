# kube-prometheus-stack

Complete Kubernetes monitoring stack including:

- **Prometheus:** Metrics collection and storage
- **Grafana:** Visualization and dashboards
- **AlertManager:** Alert routing and management
- **Node Exporter:** Node-level metrics
- **kube-state-metrics:** Kubernetes object metrics
- **Prometheus Operator:** Manages Prometheus instances

## Access

- **Grafana UI:** `http://grafana.mosher-labs.local`
- **Default Credentials:** admin / admin (change after first login!)
- **AlertManager UI:** `http://alertmanager.mosher-labs.local`

## Resource Usage

**Total estimated usage:**

- CPU: ~1.2 cores
- Memory: ~2.5GB
- Storage: ~22GB (Prometheus + Grafana + AlertManager)

## Configuration

### Prometheus

- **Retention:** 14 days
- **Storage:** 15Gi PVC
- **Scrape Interval:** 30s (default)
- **Targets:** All ServiceMonitors and PodMonitors in the cluster

### Grafana

- **Dashboards:** Pre-installed Kubernetes dashboards
- **Persistence:** 5Gi PVC for dashboard/settings storage
- **Ingress:** Traefik

### AlertManager

- **Storage:** 2Gi PVC
- **Ingress:** Traefik (`alertmanager.mosher-labs.local`)
- **External URL:** Set explicitly to the Ingress host so links in Slack
  notifications (and the AlertManager UI itself) resolve outside the
  cluster instead of defaulting to the internal Service DNS name

### Prometheus Operator Admission Webhooks

- **Mode:** Chart default (Job-based cert-create/cert-patch hooks)
- **Known issue:** On ArgoCD, these Job hooks share RBAC across Helm's
  pre/post-install hook phases with a `hook-succeeded` delete policy.
  ArgoCD deletes that RBAC after the PreSync phase, so the PostSync
  phase reports it as "missing" and the sync operation shows
  Failed/retrying. This is cosmetic — the Jobs themselves complete
  successfully and the app converges to Synced/Healthy within a
  couple of ArgoCD retries.
- **Do not switch to `admissionWebhooks.deployment.enabled: true`**
  without first installing cert-manager and setting
  `admissionWebhooks.certManager.enabled: true`. The persistent
  webhook deployment needs cert-manager to issue a certificate valid
  for the separate `*-operator-webhook` service; without it the
  webhook serves a certificate scoped to the wrong service name and
  the apiserver rejects it outright (all `PrometheusRule`
  create/update calls fail TLS verification). This was tried and
  reverted — see git history for `infrastructure/kube-prometheus-stack`.

## k3s Compatibility

The following components are **disabled** because k3s doesn't expose them:

- kubeEtcd
- kubeControllerManager
- kubeScheduler

This is normal and expected for k3s clusters.

## Post-Deployment Steps

1. **Access Grafana:**

   ```bash
   open http://grafana.mosher-labs.local
   ```

1. **Login with default credentials:** admin / admin

1. **Change admin password** (Settings → Profile → Change Password)

1. **Explore pre-installed dashboards:** Dashboards → Browse → Kubernetes,
   Start with "Kubernetes / Compute Resources / Cluster"

1. **Add custom dashboards:** Import dashboards from
   <https://grafana.com/grafana/dashboards/>, PiHole dashboard ID: 10176

## Monitoring Your Apps

To make your apps visible to Prometheus, add a `ServiceMonitor`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp
  namespace: myapp
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
    - port: metrics
      path: /metrics
```

## Troubleshooting

### Check Prometheus Targets

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Open http://localhost:9090/targets
```

### Check Grafana Logs

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana
```

### Check Prometheus Logs

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus
```

## References

- Helm Chart: <https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>
- Grafana Dashboards: <https://grafana.com/grafana/dashboards/>
- Prometheus Docs: <https://prometheus.io/docs/>
