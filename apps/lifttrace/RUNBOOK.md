# RUNBOOK.md - lifttrace

## Overview

Self-hosted [LiftTrace](https://github.com/TraceApps/lifttrace) — weight
training tracker. Single container, SQLite-backed, no telemetry. Deployed via
the `bjw-s-labs/app-template` Helm chart (LiftTrace has no official chart) with
a `cloudflared` sidecar for remote access, same pattern as `apps/couchdb`. No
inbound port is ever opened on the homelab network — the only path in is a
`cloudflared` sidecar making an *outbound* connection to Cloudflare's edge.

- **Namespace:** `lifttrace`
- **Internal URL:** not reachable from other pods — see the NetworkPolicy
  note below
- **Public URL:** `https://lifttrace.benniemosher.dev` (adjust to your
  actual zone/subdomain choice)
- **Chart:** `bjw-s-labs/app-template` v5.2.1 wrapping
  `ghcr.io/benniemosher/lifttrace:mosher-labs-f7048b0` — TEMPORARY custom
  build (upstream v1.3.1 dev branch + two of our PRs not merged upstream
  yet: [TraceApps/lifttrace#114](https://github.com/TraceApps/lifttrace/pull/114),
  [#115](https://github.com/TraceApps/lifttrace/pull/115)). Source:
  `benniemosher/lifttrace`, branch `local/mosher-labs-build`. Revert to
  `ghcr.io/traceapps/lifttrace` once both land in an upstream release.
- **Auth:** LiftTrace's own login (first account created on first run becomes
  admin). Cloudflare Access in front of the tunnel hostname is the primary
  gate — see below.

## Why this is locked down the way it is

- **No public IP/port at all.** `cloudflared` only dials *out* to
  Cloudflare. There is nothing listening on the homelab's router/firewall for
  this service.
- **Cloudflare Access in front of the tunnel hostname.** Even someone who
  discovers the hostname can't reach LiftTrace without passing an Access
  policy first (see step 2).
- **No Kubernetes Service or Ingress at all** for this app — `cloudflared`
  reaches LiftTrace over `127.0.0.1:3002` inside the same pod, which bypasses
  Service networking and isn't affected by the NetworkPolicy below — nothing
  else needs a path in.
- **NetworkPolicy denies all ingress** to the LiftTrace pod from anything
  else in the cluster (`manifests/networkpolicy.yaml`).
- **`JWT_SECRET` was generated randomly and sealed** —
  `manifests/lifttrace-sealed-secret.yaml`, already committed and safe (only
  this cluster's private key can decrypt it). LiftTrace refuses to start in
  production with its dev-default secret, so this is required, not optional,
  regardless of the Access gate above.

## Initial deployment

### 1. Provision the Tunnel + Access application

The Tunnel, its ingress config, the DNS record, and the Access application
are all provisioned by Terraform now — see
`infrastructure/cloudflare-tunnels/`, not the Zero Trust dashboard.
`lifttrace` is already an entry in that stack's `local.tunnel_apps`.

```bash
cd infrastructure/cloudflare-tunnels
terraform apply
terraform output -json tunnel_tokens | jq -r '.lifttrace'
```

Full setup (1Password credentials, the one-time state namespace, adding
further apps) is in `infrastructure/cloudflare-tunnels/RUNBOOK.md`.

### 2. Seal the tunnel token

```bash
kubectl create secret generic cloudflared-credentials \
  --namespace lifttrace \
  --from-literal=tunnel-token=<token from step 1> \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml \
  > apps/lifttrace/manifests/cloudflared-sealed-secret.yaml
```

Commit `manifests/cloudflared-sealed-secret.yaml` — it's safe to store in
git, same as the JWT secret. Until this exists, the `cloudflared` container
will crashloop (see Troubleshooting) while `app` runs fine.

### 3. Merge this PR

ArgoCD syncs automatically once merged to `main`.

### 4. Verify deployment

```bash
kubectl get pods -n lifttrace
kubectl logs -n lifttrace -l app.kubernetes.io/name=lifttrace -c app
kubectl logs -n lifttrace -l app.kubernetes.io/name=lifttrace -c cloudflared
```

Then hit `https://lifttrace.<zone>` in a browser — Access will prompt for
login first, then you should land on LiftTrace's first-run setup wizard.

### 5. First run

1. Create your account — first account created is automatically admin.
1. **Single-user mode:** if you never create a second user, LiftTrace itself
   runs without its own login prompt (Access is still gating the hostname).
   Add a second account in Settings → User Management only if someone else
   genuinely needs access.
1. **iPhone:** Safari → Share → Add to Home Screen at the tunnel URL (no
   native iOS app exists upstream yet — PWA is the supported path).
1. **Android:** the release APK enforces HTTPS-only for server connections;
   the tunnel already satisfies that (see upstream `DEPLOY.md`, "Connecting
   from Android," Path 2). Enter `https://lifttrace.<zone>` in the app's
   setup wizard.

## Integration toggles

- **`MCP_ENABLED=1`** (on) — exposes an MCP endpoint at `/api/mcp` for
  Claude Desktop/mobile/Cursor/Codex to read workout history through.
  `MCP_WRITE_ENABLED` / `MCP_DESTROY_ENABLED` stay **off** — Claude reads
  history to help plan the next session, doesn't log sets back (each
  token's own scopes are the real gate; these are just the server-wide
  ceiling on top of them).

  To connect Claude: Settings → API Tokens → new token, scope
  `mcp:read` only. In Claude's own settings (claude.ai or the app) →
  Connectors → add a custom connector, URL `https://lifttrace.<zone>/api/mcp`,
  paste the token. Token is shown once — save it somewhere (1Password)
  before closing the dialog.

- **`WEBHOOKS_ENABLED=1`** (on) — outgoing webhooks (workout completed,
  PR set, program advanced, body stat logged), configured in
  Settings → Webhooks. No webhook is configured yet — this just makes
  the feature available. Intended hook point for a future Strava-export
  relay (LiftTrace has no native Strava integration — checked upstream
  source directly, nothing there — a webhook + a small relay we'd build
  ourselves is the only path).

- **`PUBLIC_API_ENABLED`** — still off. MCP covers the Claude use case;
  nothing else needs the plain REST API yet.

## Backups

Two layers, both already available without extra setup:

- **App-level:** Settings → Backup & Restore in LiftTrace itself produces a
  ZIP (DB + uploaded media). Note the Cloudflare free-tier 100MB request-body
  cap — full-backup *restore* uploads on accounts with lots of video/import
  history can exceed it; run the restore from inside the LAN (bypassing the
  tunnel) if so. Browsing and creating backups is unaffected.
- **Infra-level:** both PVCs sit on the cluster's NFS-backed (Drobo) storage
  class, so they're durable independent of node failure already — no
  additional CronJob needed unless revision-level history becomes something
  worth restoring from (same reasoning as `apps/couchdb`'s backup section).

## Troubleshooting

### Pod not starting / cloudflared crashlooping

```bash
kubectl describe pod -n lifttrace -l app.kubernetes.io/name=lifttrace
```

Common cause: `cloudflared-credentials` sealed secret not created yet
(step 2) — the `app` container will still be `Running`, only `cloudflared`
restarts.

### Devices can't reach the hostname at all

Check the Access application's policy actually includes the identity you're
logging in with, and that the tunnel's Public Hostname config points at
`localhost:3002` (not a Service DNS name — there is no Service for this app,
cloudflared is in the same pod).

### App container fails healthcheck / won't start

```bash
kubectl logs -n lifttrace -l app.kubernetes.io/name=lifttrace -c app
```

Most likely cause is `JWT_SECRET` missing — check
`lifttrace-secrets` decrypted correctly (`kubectl get secret lifttrace-secrets
-n lifttrace`) rather than the tunnel, which only affects `cloudflared`.
