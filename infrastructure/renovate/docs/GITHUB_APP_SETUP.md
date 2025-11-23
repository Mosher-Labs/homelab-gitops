# GitHub App Setup for Self-Hosted Renovate

This guide walks through creating a GitHub App for Renovate authentication.

## Why GitHub App

- More secure than Personal Access Tokens
- Granular permissions per repository
- Appears as a bot user in PRs
- Easier to audit and manage

## Step 1: Create the GitHub App

1. Go to your organization settings: `https://github.com/organizations/Mosher-Labs/settings/apps`
1. Click **New GitHub App**
1. Fill in the details:

### Basic Information

- **GitHub App name:** `Mosher Labs Renovate`
- **Description:** `Self-hosted Renovate bot for automated dependency updates`
- **Homepage URL:** `https://github.com/Mosher-Labs/homelab-gitops`

### Webhook

- **Webhook:** Uncheck "Active" (we don't need webhooks for self-hosted)

### Permissions

#### Repository Permissions

- **Contents:** Read and write (to create branches and PRs)
- **Metadata:** Read-only (automatically selected)
- **Pull requests:** Read and write (to create and update PRs)
- **Issues:** Read and write (for Dependency Dashboard)
- **Commit statuses:** Read and write (optional, for status checks)
- **Workflows:** Read and write (to update GitHub Actions)

#### Organization Permissions

- **Members:** Read-only (optional, for assignee validation)

### Where can this GitHub App be installed

- Select **Only on this account** (Mosher-Labs organization)

### Click "Create GitHub App"

## Step 2: Generate Private Key

1. After creating the app, scroll to the bottom
1. Click **Generate a private key**
1. Save the downloaded `.pem` file securely
1. **Note the App ID** at the top of the page (you'll need this)

## Step 3: Install the GitHub App

1. In the GitHub App settings, click **Install App** in the left sidebar
1. Click **Install** next to "Mosher-Labs"
1. Choose repositories:
   - **All repositories** (recommended for org-wide updates)
   - OR **Only select repositories** (choose specific repos)
1. Click **Install**
1. **Note the Installation ID** from the URL
   (e.g., `https://github.com/organizations/Mosher-Labs/settings/installations/12345678`)

## Step 4: Prepare Credentials for Kubernetes

You'll need three values:

1. **App ID:** From the GitHub App settings page (e.g., `123456`)
1. **Installation ID:** From the installation URL (e.g., `12345678`)
1. **Private Key:** Contents of the `.pem` file

### Create the Sealed Secret

Run this command to create the sealed secret:

```bash
# Replace with your actual values
APP_ID="123456"
INSTALLATION_ID="12345678"
PRIVATE_KEY="$(cat path/to/your-app.pem)"

# Create the secret
kubectl create secret generic renovate-github-app \
  --namespace renovate \
  --from-literal=app-id="$APP_ID" \
  --from-literal=installation-id="$INSTALLATION_ID" \
  --from-literal=private-key="$PRIVATE_KEY" \
  --dry-run=client -o yaml | \
kubeseal --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml > infrastructure/renovate/manifests/sealed-secret.yaml
```

## Step 5: Commit and Deploy

```bash
git add infrastructure/renovate/
git commit -m "feat(renovate): add sealed secret for GitHub App"
git push
```

ArgoCD will automatically deploy the secret and start Renovate.

## Verification

After deployment, check the logs:

```bash
# Wait for the CronJob to run (check schedule)
kubectl --kubeconfig ~/k3s.yaml get cronjobs -n renovate

# Once a job starts, check logs
kubectl --kubeconfig ~/k3s.yaml logs -n renovate -l app=renovate --tail=100 -f
```

You should see Renovate authenticate successfully and scan your repositories.

## Troubleshooting

### "Bad credentials" error

- Verify the App ID and Installation ID are correct
- Check that the private key is complete (includes BEGIN/END markers)
- Ensure the GitHub App is installed on the repository

### "Resource not accessible by integration" error

- Check the GitHub App permissions
- Ensure "Contents" and "Pull requests" are set to "Read and write"

### No repositories found

- Verify the Installation ID matches your installation
- Check that repos are accessible by the GitHub App
- Review the app installation settings

## Security Notes

- **Private key is sensitive:** Treat it like a password
- **Sealed Secret encrypts it:** Only your cluster can decrypt
- **Rotate keys regularly:** Generate new private key every 6-12 months
- **Audit access:** Review GitHub App activity in org audit log

## References

- [Renovate GitHub App Documentation](https://docs.renovatebot.com/modules/platform/github/)
- [GitHub Apps Documentation](https://docs.github.com/en/apps)
