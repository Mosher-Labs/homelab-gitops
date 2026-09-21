# RUNBOOK.md - cloudflare-tunnels

## Overview

Terraform stack that provisions a Cloudflare Tunnel + Access application
per self-hosted app in this cluster — replaces clicking through the Zero
Trust dashboard for each new app. One entry in `local.tunnel_apps`
(`locals.tf`) gets you a Tunnel, its ingress config, a proxied DNS CNAME,
and an Access application gated by a shared "allow these emails" policy.

**Scope split from `cloudflare-management`:** that repo still owns the
zone itself and account-wide email routing — this stack only *reads* the
zone (`data.tf`) to get a `zone_id` for the DNS record. Nothing here can
create or modify a zone.

## State

State lives in **this cluster**, as a Kubernetes Secret (`backend
"kubernetes"` in `providers.tf`) — not Terraform Cloud, not committed to
git. No new account, no cost.

### One-time setup: the state namespace

```bash
kubectl create namespace terraform-state
```

This namespace is deliberately **not** an ArgoCD-managed resource and
should never become one — don't add it to any `Application`'s tracked
paths. ArgoCD's `prune: true` would treat the state Secret as an
unmanaged resource to clean up, which would destroy this stack's state.

## Credentials

Sourced from 1Password (vault: "Mosher Home"), not Keybase — this repo
already uses 1Password for the CouchDB admin credentials, so this follows
the same convention rather than `cloudflare-management`'s Keybase-based
one.

### 1Password item

Create an item (e.g. "Cloudflare Tunnels - Terraform (Mosher Labs)")
with three fields:

- `api-token` — a Cloudflare API token scoped to (on the zone(s) in
  `local.tunnel_apps`): **Zone:Read**, **DNS:Edit**, **Cloudflare
  Tunnel:Edit**, **Access: Apps and Policies:Edit**. Deliberately
  narrower than `cloudflare-management`'s org-management token — this
  one only needs to touch tunnels/DNS/Access, not the zone or account
  itself.
- `account-id` — your Cloudflare account ID (dashboard sidebar, or the
  same value already in `cloudflare-management`'s Keybase secrets).
- `allowed-emails` — comma-separated list, e.g. `you@example.com`.

### Running Terraform

```bash
export TF_VAR_cloudflare_api_token="$(op read 'op://Mosher Home/Cloudflare Tunnels - Terraform (Mosher Labs)/api-token')"
export TF_VAR_cloudflare_account_id="$(op read 'op://Mosher Home/Cloudflare Tunnels - Terraform (Mosher Labs)/account-id')"
export TF_VAR_allowed_emails="[$(op read 'op://Mosher Home/Cloudflare Tunnels - Terraform (Mosher Labs)/allowed-emails' | sed 's/\([^,]*\)/"\1"/g')]"

terraform init
terraform plan
terraform apply
```

## Adding an app

1. Add an entry to `local.tunnel_apps` in `locals.tf` (zone, subdomain,
   origin `service`, e.g. `http://localhost:<port>` for a cloudflared
   sidecar reaching its app container over loopback in the same pod).
2. `terraform apply`.
3. Get that app's connector token:

   ```bash
   terraform output -json tunnel_tokens | jq -r '.<app-key>'
   ```

4. Seal it into the app's namespace, same pattern as every app's own
   RUNBOOK (e.g. `apps/lifttrace/RUNBOOK.md`):

   ```bash
   kubectl create secret generic cloudflared-credentials \
     --namespace <app-namespace> \
     --from-literal=tunnel-token=<token from step 3> \
     --dry-run=client -o yaml | \
   kubeseal \
     --controller-namespace kube-system \
     --controller-name sealed-secrets-controller \
     --format yaml \
     > apps/<app>/manifests/cloudflared-sealed-secret.yaml
   ```

5. Commit the sealed secret, merge — ArgoCD syncs the app, which then has
   a live tunnel waiting for it.

## Removing an app

Delete its entry from `local.tunnel_apps`, `terraform apply` (tears down
the Tunnel/DNS/Access resources), then remove the app's own manifests
from this repo separately.

## Troubleshooting

### `terraform init` fails to reach the state backend

Confirm `~/k3s.yaml` is valid and the `terraform-state` namespace exists
(one-time setup above).

### `apply` fails with a 403 / authorization error

The API token is almost certainly missing one of the four scopes listed
above — check My Profile → API Tokens in the Cloudflare dashboard.

### DNS record created but the app is unreachable

Check the `cloudflared` sidecar's logs in the app's pod — it needs the
sealed `cloudflared-credentials` secret in place (see "Adding an app"
step 4) before it can connect to the tunnel it's meant to serve.
