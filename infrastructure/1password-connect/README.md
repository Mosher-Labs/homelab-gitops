# 1Password Connect Setup

This directory contains the ArgoCD Application for 1Password Connect
Server, which enables Kubernetes to securely access secrets from your
1Password vault.

## Prerequisites

Before deploying, you need to set up 1Password Connect credentials.

### Step 1: Create 1Password Connect Server

1. Go to <https://my.1password.com>
1. Navigate to **Integrations** → **Directory** → **1Password Connect**
1. Click **Set up Server**
1. Give it a name (e.g., "Homelab K3s Cluster")
1. Select the vaults you want to grant access to
1. Click **Save & Get Credentials**
1. Download the `1password-credentials.json` file

### Step 2: Create Kubernetes Secret

Create the credentials secret in your cluster:

```bash
kubectl create namespace onepassword

kubectl create secret generic onepassword-credentials \
  --from-file=1password-credentials.json=\
/path/to/downloaded/1password-credentials.json \
  -n onepassword
```

### Step 3: Create Access Token

The operator needs a token to communicate with the Connect server:

```bash
# Generate a random token
OP_CONNECT_TOKEN=$(openssl rand -base64 32)

# Create the token secret
kubectl create secret generic onepassword-token \
  --from-literal=token=$OP_CONNECT_TOKEN \
  -n onepassword

# Save this token - you'll need it for configuring SecretStores
echo "Your 1Password Connect Token: $OP_CONNECT_TOKEN"
```

### Step 4: Deploy via ArgoCD

Once the secrets are created, ArgoCD will automatically deploy 1Password Connect.

## Disaster Recovery

**CRITICAL**: Save these items in a secure location:

- `1password-credentials.json` file
- The generated `OP_CONNECT_TOKEN` value

If your cluster is destroyed, you'll need both to restore 1Password integration.

## Using 1Password Secrets

After deployment, create a `SecretStore` and `ExternalSecret` in your app namespace:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: onepassword-store
  namespace: your-app-namespace
spec:
  provider:
    onepassword:
      connectHost: http://onepassword-connect:8080
      vaults:
        homelab: 1  # Your vault ID
      auth:
        secretRef:
          connectTokenSecretRef:
            name: onepassword-token
            key: token
```

See the External Secrets Operator documentation for more examples.
