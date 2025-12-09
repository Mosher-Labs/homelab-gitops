# Self-Hosted Renovate

Self-hosted Renovate running as a Kubernetes CronJob for automated dependency
updates across multiple GitHub organizations.

## Overview

- **Deployment:** CronJob (runs daily at 2am)
- **Authentication:** GitHub App
- **Repositories:** Autodiscover repos with `renovate.json` in Mosher-Labs and
  acebackapp orgs
- **Monitoring:** Grafana dashboard for job history and status

## Quick Start

### 1. Create GitHub App

Follow the detailed guide in
[docs/GITHUB_APP_SETUP.md](docs/GITHUB_APP_SETUP.md) to:

1. Create a GitHub App in the Mosher-Labs organization
1. Generate a private key
1. Install the app on each organization (Mosher-Labs, acebackapp, etc.)
1. Note the App ID (installation IDs are not needed with native GitHub App auth)

### 2. Create Sealed Secret

```bash
# Replace with your actual values
APP_ID="your-app-id"
PRIVATE_KEY="$(cat path/to/your-app.pem)"

# Create the sealed secret
kubectl create secret generic renovate-github-app \
  --namespace renovate \
  --from-literal=app-id="$APP_ID" \
  --from-literal=private-key="$PRIVATE_KEY" \
  --dry-run=client -o yaml | \
kubeseal --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml > infrastructure/renovate/manifests/sealed-secret.yaml
```

### 3. Remove Template and Commit

```bash
# Remove the template file
rm infrastructure/renovate/manifests/sealed-secret-template.yaml

# Commit the sealed secret
git add infrastructure/renovate/manifests/sealed-secret.yaml
git commit -m "feat(renovate): add GitHub App sealed secret"
git push
```

### 4. Deploy

ArgoCD will automatically detect and deploy Renovate.

Verify deployment:

```bash
# Check CronJob
kubectl --kubeconfig ~/k3s.yaml get cronjob -n renovate

# Check for running jobs (may need to wait up to 5 minutes)
kubectl --kubeconfig ~/k3s.yaml get jobs -n renovate

# View logs
kubectl --kubeconfig ~/k3s.yaml logs -n renovate -l app=renovate --tail=100 -f
```

## Configuration

### Schedule

The CronJob runs **daily at 2am** (`0 2 * * *`).

To change the schedule, edit
[manifests/cronjob.yaml](manifests/cronjob.yaml):

```yaml
spec:
  schedule: "0 */6 * * *"  # Every 6 hours
```

### Repository Configuration

Renovate will autodiscover all repositories in organizations where the GitHub
App is installed that have a `renovate.json` file.

The root `renovate.json` configuration is embedded in
[manifests/configmap.yaml](manifests/configmap.yaml).

To add a new repository:

1. Add a `renovate.json` to the repository root
1. Renovate will automatically detect it on the next run

### Suspend CronJob

To temporarily disable Renovate:

```bash
kubectl --kubeconfig ~/k3s.yaml patch cronjob renovate -n renovate \
  -p '{"spec":{"suspend":true}}'
```

To re-enable:

```bash
kubectl --kubeconfig ~/k3s.yaml patch cronjob renovate -n renovate \
  -p '{"spec":{"suspend":false}}'
```

### Manual Trigger

To manually run Renovate outside the schedule:

```bash
kubectl --kubeconfig ~/k3s.yaml create job -n renovate \
  renovate-manual-$(date +%s) --from=cronjob/renovate
```

## Monitoring

### Grafana Dashboard

A Grafana dashboard is automatically deployed showing:

- Active jobs
- Last scheduled time
- Successful/failed job counts
- Job duration history
- Recent job list

Access it in Grafana under **Dashboards → Renovate CronJob**

### Logs

View Renovate logs in real-time:

```bash
# Wait for a job to start
kubectl --kubeconfig ~/k3s.yaml get jobs -n renovate -w

# View logs
kubectl --kubeconfig ~/k3s.yaml logs -n renovate \
  -l app=renovate --tail=100 -f
```

### Metrics

Renovate CronJob metrics are scraped by kube-state-metrics and available in
Prometheus:

- `kube_cronjob_status_active{cronjob="renovate"}`
- `kube_cronjob_status_last_schedule_time{cronjob="renovate"}`
- `kube_job_status_succeeded{job_name=~"renovate-.*"}`
- `kube_job_status_failed{job_name=~"renovate-.*"}`

## Troubleshooting

### No Jobs Running

Check if the CronJob is suspended:

```bash
kubectl --kubeconfig ~/k3s.yaml get cronjob renovate -n renovate -o yaml | \
  grep suspend
```

If `suspend: true`, unsuspend it:

```bash
kubectl --kubeconfig ~/k3s.yaml patch cronjob renovate -n renovate \
  -p '{"spec":{"suspend":false}}'
```

### Authentication Errors

Verify the sealed secret was created correctly:

```bash
# Check if secret exists
kubectl --kubeconfig ~/k3s.yaml get secret renovate-github-app -n renovate

# Verify keys are present
kubectl --kubeconfig ~/k3s.yaml get secret renovate-github-app -n renovate \
  -o jsonpath='{.data}' | jq 'keys'
```

Should show: `["app-id", "private-key"]`

### Job Failing

Check the job logs:

```bash
# List recent jobs
kubectl --kubeconfig ~/k3s.yaml get jobs -n renovate

# View logs for latest job
kubectl --kubeconfig ~/k3s.yaml logs -n renovate \
  -l app=renovate --tail=200
```

Common issues:

- **Bad credentials:** Verify App ID and private key are correct
- **Rate limiting:** Wait or reduce frequency
- **Repository access:** Ensure GitHub App is installed on the repository

### No Repositories Found

Renovate uses autodiscovery. Check:

1. The GitHub App is installed on repositories
1. Repositories have a `renovate.json` file
1. The autodiscoverFilter matches: `"Mosher-Labs/*"` or `"acebackapp/*"`

View autodiscovery logs:

```bash
kubectl --kubeconfig ~/k3s.yaml logs -n renovate \
  -l app=renovate --tail=200 | grep -i autodiscover
```

## Updating Configuration

### Update Renovate Image

Edit [manifests/cronjob.yaml](manifests/cronjob.yaml):

```yaml
image: renovate/renovate:37.100.0  # Pin to specific version
```

### Update Config

Edit [manifests/configmap.yaml](manifests/configmap.yaml) and commit.
ArgoCD will automatically apply changes.

### Rotate GitHub App Key

1. Generate new private key in GitHub App settings
1. Create new sealed secret
1. Apply to cluster (ArgoCD will update)
1. Delete old secret

## Architecture

```
┌─────────────────────────────────────────────┐
│          Kubernetes Cluster (k3s)           │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │      renovate namespace               │ │
│  │                                       │ │
│  │  ┌─────────────────────────────────┐ │ │
│  │  │  CronJob: renovate              │ │ │
│  │  │  Schedule: */5 * * * *          │ │ │
│  │  │  Image: renovate/renovate       │ │ │
│  │  └─────────────┬───────────────────┘ │ │
│  │                │                     │ │
│  │                ▼                     │ │
│  │  ┌─────────────────────────────────┐ │ │
│  │  │  Job: renovate-<timestamp>      │ │ │
│  │  │  - Reads ConfigMap              │ │ │
│  │  │  - Uses GitHub App credentials  │ │ │
│  │  │  - Scans repos for updates      │ │ │
│  │  │  - Creates PRs                  │ │ │
│  │  └─────────────────────────────────┘ │ │
│  │                                       │ │
│  └───────────────────────────────────────┘ │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │      monitoring namespace             │ │
│  │                                       │ │
│  │  ┌─────────────────────────────────┐ │ │
│  │  │  Prometheus                     │ │ │
│  │  │  - Scrapes kube-state-metrics   │ │ │
│  │  │  - Stores job metrics           │ │ │
│  │  └─────────────┬───────────────────┘ │ │
│  │                │                     │ │
│  │                ▼                     │ │
│  │  ┌─────────────────────────────────┐ │ │
│  │  │  Grafana                        │ │ │
│  │  │  - Renovate CronJob dashboard   │ │ │
│  │  │  - Job history visualization    │ │ │
│  │  └─────────────────────────────────┘ │ │
│  │                                       │ │
│  └───────────────────────────────────────┘ │
│                                             │
└─────────────────────────────────────────────┘
                    │
                    ▼
          ┌─────────────────┐
          │  GitHub API     │
          │  - Authenticate │
          │  - Scan repos   │
          │  - Create PRs   │
          └─────────────────┘
```

## References

- [Renovate Documentation](https://docs.renovatebot.com/)
- [Self-Hosting Guide](https://docs.renovatebot.com/self-hosting/)
- [GitHub App Authentication](https://docs.renovatebot.com/modules/platform/github/)
- [Configuration Options](https://docs.renovatebot.com/configuration-options/)
