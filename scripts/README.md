# Homelab Scripts

## TP-Link Device Sync

The `sync-tplink-devices.py` script automates the discovery and
configuration of TP-Link smart home devices on your IoT network.

### What it does

1. **Discovers TP-Link devices** on your IoT network (192.168.3.0/24)
1. **Creates DHCP reservations** in UniFi controller so devices keep
   their IPs
1. **Updates Homebridge config** with all discovered devices
1. **Creates a GitHub PR** with the changes
1. **Posts to Slack** with a link to review the PR

### Architecture

The script runs as a **Kubernetes CronJob** inside your cluster,
giving it access to:

- Internal IoT network (192.168.3.x)
- UniFi controller (192.168.202.1)
- Homebridge configuration

## Deployment

### 1. Build and Push Docker Image

```bash
cd scripts
docker build -t ghcr.io/mosher-labs/tplink-sync:latest .
docker push ghcr.io/mosher-labs/tplink-sync:latest
```

### 2. Create Sealed Secrets

First, create a `secrets.env` file (DON'T commit this!):

```bash
cat > secrets.env <<EOF
UNIFI_USERNAME=your-unifi-username
UNIFI_PASSWORD=your-unifi-password
GITHUB_TOKEN=ghp_your_github_personal_access_token
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
EOF
```

Then generate the sealed secret:

```bash
kubectl create secret generic tplink-sync-secrets \
  --from-env-file=secrets.env \
  --namespace=tplink-sync \
  --dry-run=client -o yaml | \
kubeseal --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml > ../apps/tplink-sync/manifests/sealed-secret.yaml

# Delete the plaintext file!
rm secrets.env
```

### 3. Deploy via ArgoCD

```bash
kubectl apply -f apps/tplink-sync/application.yaml
```

ArgoCD will automatically:

- Create the `tplink-sync` namespace
- Deploy the sealed secrets
- Create the CronJob

### 4. Test Manually

Trigger a manual run:

```bash
kubectl create job --from=cronjob/tplink-sync tplink-sync-manual-test -n tplink-sync
kubectl logs -f job/tplink-sync-manual-test -n tplink-sync
```

## How It Works

```
Every day @ 2 AM
     ↓
CronJob runs in K8s cluster
     ↓
Clone Git repo
     ↓
Discover TP-Link devices (192.168.3.x)
     ↓
Create DHCP reservations in UniFi
     ↓
Update Homebridge config.json
     ↓
Commit & push to new branch
     ↓
Create GitHub PR
     ↓
Post to Slack
     ↓
You review & merge PR
     ↓
ArgoCD syncs changes
     ↓
Homebridge sees new devices ✅
```

## Requirements

### UniFi Controller Credentials

1. Navigate to your UniFi controller at <https://192.168.202.1:8443>
1. Go to Settings → Admins
1. Create a new admin account for automation (or use existing)
1. Note the username and password

### GitHub Personal Access Token

1. Go to <https://github.com/settings/tokens>
1. Click "Generate new token (classic)"
1. Give it a name: "TP-Link Sync Bot"
1. Select scopes:
   - `repo` (full control)
   - `workflow` (if you want to trigger workflows)
1. Copy the token (starts with `ghp_`)

### Slack Webhook

1. Go to <https://api.slack.com/messaging/webhooks>
1. Create a new incoming webhook
1. Select the channel for notifications
1. Copy the webhook URL

## Local Testing

Test the script locally before deploying:

```bash
# Install dependencies
pip3 install -r requirements.txt

# Set environment variables
export UNIFI_HOST="https://192.168.202.1:8443"
export UNIFI_USERNAME="your-username"
export UNIFI_PASSWORD="your-password"
export GITHUB_TOKEN="ghp_your_token"
export GITHUB_REPOSITORY="Mosher-Labs/homelab-gitops"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
export HOMEBRIDGE_CONFIG="/tmp/test-config.json"

# Copy current config to test location
cp apps/homebridge/config.json /tmp/test-config.json

# Run the script
python3 sync-tplink-devices.py
```

## Troubleshooting

**No devices discovered:**

- Verify devices are powered on
- Check firewall rules allow traffic from K8s cluster to IoT network
  (192.168.3.x)
- Test connectivity: `kubectl exec -n tplink-sync <pod> -- ping
  192.168.3.195`

**UniFi API errors:**

- Verify credentials are correct
- Check UniFi controller is accessible from cluster
- Ensure admin account has sufficient permissions

**GitHub PR creation fails:**

- Verify GitHub token has `repo` scope
- Check token hasn't expired
- Verify repository name is correct

**Homebridge not seeing devices:**

- Verify Homebridge config was updated
- Check ArgoCD synced the changes
- Restart Homebridge pod: `kubectl rollout restart deployment/homebridge
  -n homebridge`

**Slack notifications not working:**

- Verify webhook URL is correct
- Check webhook hasn't been revoked
- Test webhook manually with curl (see webhook documentation)

## Customization

### Change Schedule

Edit `apps/tplink-sync/manifests/cronjob.yaml`:

```yaml
spec:
  # Run every 6 hours instead of daily
  schedule: "0 */6 * * *"
```

### Change Target Network

Edit the script to scan a different subnet:

```python
devices = asyncio.run(discover_tplink_devices(network='192.168.10.255'))
```
