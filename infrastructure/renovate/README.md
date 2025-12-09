# Self-Hosted Renovate

Self-hosted Renovate running as Kubernetes CronJobs for automated dependency
updates across multiple GitHub organizations.

## Overview

- **Deployment:** Separate CronJob per organization (staggered schedules)
- **Authentication:** GitHub App with installation tokens
- **Repositories:** Autodiscover repos with `renovate.json` in each org
- **Monitoring:** Grafana dashboard for job history and status

## Current Organizations

| Organization | CronJob | Schedule | Installation ID Key |
|--------------|---------|----------|---------------------|
| Mosher-Labs | `renovate-mosher-labs` | 2:00 AM | `installation-id-mosher-labs` |
| acebackapp | `renovate-acebackapp` | 2:15 AM | `installation-id-acebackapp` |

## Quick Start

### 1. Create GitHub App

Follow the detailed guide in
[docs/GITHUB_APP_SETUP.md](docs/GITHUB_APP_SETUP.md) to:

1. Create a GitHub App in your primary organization
1. Generate a private key
1. Install the app on each organization you want to manage
1. Note the App ID and each Installation ID

### 2. Get Installation IDs

For each organization where the app is installed, get the installation ID:

```bash
# List installations for the GitHub App
gh api /user/installations --jq '.installations[] | "\(.account.login): \(.id)"'
```

### 3. Create Sealed Secret

```bash
# Replace with your actual values
APP_ID="your-app-id"
PRIVATE_KEY="$(cat path/to/your-app.pem)"
MOSHER_LABS_INSTALLATION_ID="your-mosher-labs-installation-id"
ACEBACKAPP_INSTALLATION_ID="your-acebackapp-installation-id"

# Create the sealed secret with all installation IDs
kubectl create secret generic renovate-github-app \
  --namespace renovate \
  --from-literal=app-id="$APP_ID" \
  --from-literal=private-key="$PRIVATE_KEY" \
  --from-literal=installation-id-mosher-labs="$MOSHER_LABS_INSTALLATION_ID" \
  --from-literal=installation-id-acebackapp="$ACEBACKAPP_INSTALLATION_ID" \
  --dry-run=client -o yaml | \
kubeseal --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml > infrastructure/renovate/manifests/sealed-secret.yaml
```

### 4. Deploy

ArgoCD will automatically detect and deploy all Renovate CronJobs.

Verify deployment:

```bash
# Check CronJobs
kubectl --kubeconfig ~/k3s.yaml get cronjob -n renovate

# Check for running jobs
kubectl --kubeconfig ~/k3s.yaml get jobs -n renovate

# View logs for a specific org
kubectl --kubeconfig ~/k3s.yaml logs -n renovate -l org=mosher-labs --tail=100
```

## Adding a New Organization

To add Renovate support for a new organization:

### 1. Install the GitHub App

Go to the GitHub App settings and install it on the new organization.

### 2. Get the Installation ID

```bash
gh api /user/installations --jq '.installations[] | select(.account.login=="NEW_ORG") | .id'
```

### 3. Update the Sealed Secret

Add the new installation ID to the secret:

```bash
# Add to the secret creation command:
--from-literal=installation-id-neworg="$NEWORG_INSTALLATION_ID"
```

### 4. Create a New CronJob

Copy an existing cronjob file and modify:

```bash
cp manifests/cronjob-mosher-labs.yaml manifests/cronjob-neworg.yaml
```

Update the new file:

- Change `metadata.name` to `renovate-neworg`
- Change `metadata.labels.org` and `spec.jobTemplate.metadata.labels.org`
- Update `spec.schedule` to a different time (stagger by 15 minutes)
- Change `GITHUB_INSTALLATION_ID` secretKeyRef to `installation-id-neworg`
- Change `RENOVATE_AUTODISCOVER_FILTER` to `neworg/*`

### 5. Commit and Deploy

```bash
git add manifests/cronjob-neworg.yaml
git commit -m "feat(renovate): add neworg organization"
git push
```

## Configuration

### Schedules

CronJobs are staggered by 15 minutes to avoid running simultaneously:

- Mosher-Labs: `0 2 * * *` (2:00 AM)
- acebackapp: `15 2 * * *` (2:15 AM)

### Shared Configuration

The shared Renovate configuration is in
[manifests/configmap.yaml](manifests/configmap.yaml). This applies to all orgs.

Each CronJob overrides `autodiscoverFilter` via environment variable to limit
which repositories it processes.

### Manual Trigger

To manually run Renovate for a specific organization:

```bash
# Mosher-Labs
kubectl --kubeconfig ~/k3s.yaml create job -n renovate \
  renovate-mosher-labs-manual-$(date +%s) --from=cronjob/renovate-mosher-labs

# acebackapp
kubectl --kubeconfig ~/k3s.yaml create job -n renovate \
  renovate-acebackapp-manual-$(date +%s) --from=cronjob/renovate-acebackapp
```

### Suspend/Resume

To suspend a specific organization's CronJob:

```bash
kubectl --kubeconfig ~/k3s.yaml patch cronjob renovate-mosher-labs -n renovate \
  -p '{"spec":{"suspend":true}}'
```

## Monitoring

### Logs

View logs for a specific organization:

```bash
# Mosher-Labs
kubectl --kubeconfig ~/k3s.yaml logs -n renovate -l org=mosher-labs --tail=100 -f

# acebackapp
kubectl --kubeconfig ~/k3s.yaml logs -n renovate -l org=acebackapp --tail=100 -f

# All organizations
kubectl --kubeconfig ~/k3s.yaml logs -n renovate -l app=renovate --tail=100 -f
```

### Grafana Dashboard

A Grafana dashboard is automatically deployed showing:

- Active jobs per organization
- Last scheduled time
- Successful/failed job counts
- Job duration history

## Troubleshooting

### Authentication Errors

Verify the sealed secret has all required keys:

```bash
kubectl --kubeconfig ~/k3s.yaml get secret renovate-github-app -n renovate \
  -o jsonpath='{.data}' | jq 'keys'
```

Should show:

```json
["app-id", "installation-id-acebackapp", "installation-id-mosher-labs", "private-key"]
```

### Job Failing for One Org

Check the logs for that specific organization:

```bash
kubectl --kubeconfig ~/k3s.yaml logs -n renovate -l org=acebackapp --tail=200
```

Common issues:

- **Bad installation ID:** Verify the installation ID is correct for that org
- **App not installed:** Ensure the GitHub App is installed on that organization
- **Repository access:** Check the app has access to repositories in that org

### No Repositories Found

1. Verify the GitHub App is installed on the organization
1. Check repositories have a `renovate.json` file
1. View autodiscovery logs:

```bash
kubectl --kubeconfig ~/k3s.yaml logs -n renovate -l org=acebackapp \
  --tail=200 | grep -i autodiscover
```

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│              Kubernetes Cluster (k3s)                       │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │                 renovate namespace                     │ │
│  │                                                        │ │
│  │  ┌────────────────────┐  ┌────────────────────┐       │ │
│  │  │ CronJob:           │  │ CronJob:           │  ...  │ │
│  │  │ renovate-mosher-   │  │ renovate-acebackapp│       │ │
│  │  │ labs               │  │                    │       │ │
│  │  │ Schedule: 2:00 AM  │  │ Schedule: 2:15 AM  │       │ │
│  │  └─────────┬──────────┘  └─────────┬──────────┘       │ │
│  │            │                       │                   │ │
│  │            ▼                       ▼                   │ │
│  │  ┌────────────────────────────────────────────┐       │ │
│  │  │ Init Container: token-generator            │       │ │
│  │  │ - Generates JWT from App credentials       │       │ │
│  │  │ - Exchanges for installation access token  │       │ │
│  │  └────────────────────────────────────────────┘       │ │
│  │            │                                           │ │
│  │            ▼                                           │ │
│  │  ┌────────────────────────────────────────────┐       │ │
│  │  │ Container: renovate                        │       │ │
│  │  │ - Uses installation token                  │       │ │
│  │  │ - Autodiscovers repos for that org         │       │ │
│  │  │ - Creates dependency update PRs            │       │ │
│  │  └────────────────────────────────────────────┘       │ │
│  │                                                        │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   GitHub API    │
                    │ - Mosher-Labs/* │
                    │ - acebackapp/*  │
                    │ - (future orgs) │
                    └─────────────────┘
```

## References

- [Renovate Documentation](https://docs.renovatebot.com/)
- [Self-Hosting Guide](https://docs.renovatebot.com/self-hosting/)
- [GitHub App Authentication](https://docs.renovatebot.com/modules/platform/github/)
- [Configuration Options](https://docs.renovatebot.com/configuration-options/)
