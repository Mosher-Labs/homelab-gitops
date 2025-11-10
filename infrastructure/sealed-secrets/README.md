# Sealed Secrets

Sealed Secrets allows you to encrypt Kubernetes secrets so they can be
safely stored in Git repositories, even public ones.

## How It Works

- Controller runs in your cluster with a private encryption key
- You use `kubeseal` CLI with the public key to encrypt secrets
- Encrypted SealedSecret goes to Git (safe to be public!)
- Controller decrypts it in the cluster and creates a regular Secret

## Security Model

- Public key encryption (like HTTPS certificates)
- Only the controller can decrypt sealed secrets
- Without the private key, encrypted secrets are useless
- Safe to commit encrypted secrets to public repos

## Installing kubeseal CLI

### macOS

```bash
brew install kubeseal
```

### Linux

```bash
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.4/kubeseal-0.27.4-linux-amd64.tar.gz
tar -xvzf kubeseal-0.27.4-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Creating a SealedSecret

### Method 1: From existing secret

```bash
# Get the public key (save for later use)
kubeseal --fetch-cert --controller-namespace=kube-system \
  > pub-sealed-secrets.pem

# Seal an existing secret
kubectl get secret my-secret -n my-namespace -o yaml | \
  kubeseal --format=yaml \
    --cert=pub-sealed-secrets.pem \
    --controller-namespace=kube-system > sealed-my-secret.yaml

# Commit to Git
git add sealed-my-secret.yaml
git commit -m "Add sealed secret"
```

### Method 2: From scratch

```bash
# Create a secret locally (DON'T commit this!)
kubectl create secret generic my-secret \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml > temp-secret.yaml

# Seal it
kubeseal --format=yaml \
  --cert=pub-sealed-secrets.pem < temp-secret.yaml > sealed-secret.yaml

# Clean up the plaintext version
rm temp-secret.yaml

# Commit the sealed version
git add sealed-secret.yaml
```

## Disaster Recovery

**CRITICAL**: If you lose the sealing key and your cluster is destroyed,
you cannot decrypt your sealed secrets!

### Backup the Sealing Key

```bash
# Backup the private key
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-master-key-backup.yaml

# Store this file in a SECURE location:
# - Password manager (1Password, Bitwami, etc.)
# - Encrypted USB drive
# - Secure cloud storage (encrypted)
# - DO NOT commit to Git!
```

### Restore After Cluster Rebuild

```bash
# Install Sealed Secrets controller (via ArgoCD)
# Before it generates a new key, restore the old one:
kubectl apply -f sealed-secrets-master-key-backup.yaml

# Restart the controller to use the restored key:
kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Your SealedSecrets will now decrypt with the restored key!
```

## Using in Apps

In your app's directory, create a SealedSecret:

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-app-secrets
  namespace: my-app
spec:
  encryptedData:
    password: AgB8... # Encrypted with kubeseal
  template:
    metadata:
      name: my-app-secrets
```

The controller will automatically create a Secret from this:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secrets
  namespace: my-app
data:
  password: c3VwZXJzZWNyZXQ=  # base64 encoded, decrypted by controller
```

## Best Practices

- Backup the sealing key immediately after installation
- Never commit unsealed secrets to Git
- Use different namespaces for different apps (scope-based encryption)
- Rotate secrets periodically
- Test your backup restoration process

## Troubleshooting

### SealedSecret not decrypting

```bash
# Check controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=sealed-secrets

# Check the SealedSecret status
kubectl describe sealedsecret my-secret -n my-namespace
```

### Re-seal after key rotation

```bash
# Fetch the new public cert
kubeseal --fetch-cert --controller-namespace=kube-system \
  > pub-sealed-secrets-new.pem

# Re-seal your secrets with the new cert
```
