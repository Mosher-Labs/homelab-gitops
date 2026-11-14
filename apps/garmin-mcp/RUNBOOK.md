# RUNBOOK.md - garmin-mcp

## Overview

[Garmin MCP](https://github.com/Taxuspt/garmin_mcp) lets Claude (claude.ai,
web and mobile) read Garmin Connect health, activity and training data, and
create and schedule workouts. It runs on the `bjw-s-labs/app-template` chart
with a `cloudflared` sidecar, the same pattern as `apps/lifttrace`.

- **Namespace:** `garmin-mcp`
- **Public URL:** `https://garmin.benniemosher.dev/mcp`
- **Image:** `ghcr.io/benniemosher/garmin-mcp`. Upstream publishes no image,
  so `benniemosher/garmin_mcp` builds one from branch
  `local/mosher-labs-build` (upstream `main` plus one workflow,
  `.github/workflows/mosher-labs-image.yml`). The tag is
  `mosher-labs-<short sha>`, pinned by digest in `application.yaml`.
- **Auth:** every `/mcp` call must send `Authorization: Bearer
  <GARMIN_MCP_HTTP_TOKEN>`, checked by the server. Cloudflare Access gates the
  rest of the hostname, with a bypass for `/mcp` because the claude.ai
  connector cannot pass an Access login. `/healthz` and `/readyz` are open on
  the pod but sit behind Access on the hostname.
- **Garmin login:** OAuth tokens on the `data` volume at `/data/tokens`,
  written once by `garmin-mcp-auth`. They last about six months. No Garmin
  password is stored in the cluster.
- **Tools:** `GARMIN_TOOL_PROFILE=workouts,health,activities,training`, with
  `delete_activity` disabled. A recorded activity has no undo in Garmin
  Connect, and planning never needs to delete one.

## Initial deployment

### 1. Provision the tunnel

`garmin-mcp` is an entry in `infrastructure/cloudflare-tunnels/locals.tf`.
Apply that stack as its RUNBOOK describes, then read the connector token:

```bash
cd infrastructure/cloudflare-tunnels
terraform apply
terraform output -json tunnel_tokens | jq -r '."garmin-mcp"'
```

### 2. Seal the tunnel token

```bash
kubectl create secret generic cloudflared-credentials \
  --namespace garmin-mcp \
  --from-literal=tunnel-token=<token from step 1> \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml \
  > apps/garmin-mcp/manifests/cloudflared-sealed-secret.yaml
```

Commit it to this PR. Until it exists, `cloudflared` crashloops while `app`
runs.

### 3. Merge

ArgoCD syncs `apps/garmin-mcp/application.yaml` automatically.

### 4. Log in to Garmin once

The pod stays not Ready (`/readyz` returns 503) until this is done. The
container already has `GARMINTOKENS=/data/tokens`, so the tokens land on the
volume. It prompts for your Garmin email, password and MFA code:

```bash
kubectl exec -it -n garmin-mcp deploy/garmin-mcp -c app -- garmin-mcp-auth
kubectl rollout restart -n garmin-mcp deploy/garmin-mcp
```

The server logs in from the tokens only at startup, so the restart is needed.
Run the same two commands when the tokens expire, about every six months, or
add `--force-reauth` if Garmin rejects them.

### 5. Add the connector in Claude

The MCP bearer token was generated and sealed in
`manifests/garmin-mcp-sealed-secret.yaml`. Save the plaintext in 1Password
("Mosher Home" vault) before you delete the local copy.

In claude.ai, Settings → Connectors → Add custom connector:

- URL: `https://garmin.benniemosher.dev/mcp`
- Token: the `GARMIN_MCP_HTTP_TOKEN` value

## Rotating the MCP token

```bash
openssl rand -hex 32 | tr -d '\n' > /tmp/garmin-mcp-token
kubectl create secret generic garmin-mcp-secrets \
  --namespace garmin-mcp \
  --from-file=GARMIN_MCP_HTTP_TOKEN=/tmp/garmin-mcp-token \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml \
  > apps/garmin-mcp/manifests/garmin-mcp-sealed-secret.yaml
```

Commit, merge, restart the deployment, update the connector in Claude, and
delete `/tmp/garmin-mcp-token`.

## Updating the image

1. In `benniemosher/garmin_mcp`, merge upstream `main` into
   `local/mosher-labs-build` and push. The workflow builds
   `mosher-labs-<short sha>`.
2. Read the digest and update `application.yaml`:

   ```bash
   crane digest ghcr.io/benniemosher/garmin-mcp:mosher-labs-<short sha>
   ```

## Troubleshooting

### Pod not Ready

```bash
kubectl logs -n garmin-mcp deploy/garmin-mcp -c app
```

"Garmin login from saved tokens failed and no credentials were provided"
means step 4 has not run, or the tokens expired. Run it again.

### Claude reports 401

The connector's token does not match `GARMIN_MCP_HTTP_TOKEN`. Check the
secret decrypted (`kubectl get secret garmin-mcp-secrets -n garmin-mcp`) and
re-enter the token in the connector.

### Claude gets an Access login page or a redirect

The `/mcp` bypass application is missing. Check `terraform plan` in
`infrastructure/cloudflare-tunnels` shows no changes.
