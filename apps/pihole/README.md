# PiHole

Network-wide ad blocking and DNS server for the homelab.

## Overview

PiHole provides DNS-based ad blocking and local DNS resolution for all devices
on the network. Deployed via the mojo2600/pihole-kubernetes Helm chart.

## Access

- **Web UI:** `http://pihole.mosher-labs.local`
- **DNS Service:** `192.168.87.100` (MetalLB LoadBalancer)
- **Admin Password:** Stored in sealed secret

## Configuration

### DNS Settings

- **Upstream DNS:** Cloudflare (1.1.1.1, 1.0.0.1)
- **DNSSEC:** Enabled
- **Port:** 53 (TCP and UDP)

### Monitoring

PiHole exports metrics to Prometheus via a **separate deployment** of
`pihole-exporter` (not a sidecar to avoid circular dependencies):

- **Exporter:** ekofr/pihole-exporter:latest
- **Metrics Port:** 9617
- **ServiceMonitor:** Enabled (automatic scraping by Prometheus)
- **Deployment:** Separate pod that connects to PiHole web API

**Available Metrics:**

- `pihole_domains_being_blocked` - Total domains on blocklist
- `pihole_dns_queries_today` - DNS queries in the last 24 hours
- `pihole_ads_blocked_today` - Ads blocked in the last 24 hours
- `pihole_ads_percentage_today` - Percentage of ads blocked
- `pihole_unique_domains` - Unique domains queried
- `pihole_queries_forwarded` - Queries forwarded to upstream DNS
- `pihole_queries_cached` - Queries answered from cache
- `pihole_status` - Pi-hole enabled status (1 = enabled, 0 = disabled)

### Resource Limits

**PiHole:**

- CPU: 100m requests, 200m limits
- Memory: 128Mi requests, 256Mi limits
- Storage: 1Gi PVC

**Exporter Sidecar:**

- CPU: 25m requests, 50m limits
- Memory: 64Mi requests, 128Mi limits

## Grafana Dashboard

Import the official PiHole dashboard from Grafana:

1. Navigate to Grafana → Dashboards → Import
1. Enter Dashboard ID: **10176**
1. Select Prometheus as the data source
1. Click Import

This provides visualizations for:

- DNS queries over time
- Top blocked domains
- Query types breakdown
- Cache hit rate
- Upstream server response times

## Troubleshooting

### Check PiHole Status

```bash
kubectl get pods -n pihole
kubectl logs -n pihole -l app=pihole
```

### Check Exporter Metrics

```bash
# Port-forward to the metrics port
kubectl port-forward -n pihole svc/pihole-web 9617:9617

# Query metrics
curl http://localhost:9617/metrics
```

### Verify Prometheus Scraping

```bash
# Check if PodMonitor was created
kubectl get podmonitor -n pihole

# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Open http://localhost:9090/targets and look for pihole
```

### DNS Not Working

1. Verify LoadBalancer IP is assigned: `kubectl get svc -n pihole`
1. Check DNS can be queried: `dig @192.168.87.100 google.com`
1. Verify upstream DNS is reachable from pod
1. Check PiHole logs for errors

## References

- Helm Chart: <https://github.com/MoJo2600/pihole-kubernetes>
- PiHole Exporter: <https://github.com/eko/pihole-exporter>
- Grafana Dashboard: <https://grafana.com/grafana/dashboards/10176>
- PiHole Docs: <https://docs.pi-hole.net/>
