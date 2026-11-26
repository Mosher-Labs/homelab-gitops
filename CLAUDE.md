# Mosher Labs Homelab GitOps - Project Memory

This file contains persistent context for Claude Code sessions on this project.
It will be automatically loaded at the start of every session.

## Project Overview

This is a GitOps repository managing a 3-node k3s Kubernetes homelab cluster using
ArgoCD. The cluster runs smart home automation, media services, and networking
infrastructure.

**Key Details:**

- **Cluster Type:** 2-node k3s (hp-elitedesk, battlestation-ubuntu)
- **GitOps Tool:** ArgoCD (self-managed from this repo)
- **Deployment Pattern:** OSS Helm charts with ArgoCD Applications
- **Network:** nodes and MetalLB pool on the Homelab VLAN (192.168.87.0/24); smart
  devices on the IoT VLAN (192.168.3.0/24)
- **Ingress:** Traefik (*.mosher-labs.local for internal access)
- **Storage:** NFS backed (Drobo) + local persistent volumes
- **Timezone:** America/Denver

## Critical Architecture Patterns

### Deployment Pattern: OSS Helm Charts

**IMPORTANT:** We use well-maintained open-source Helm charts, NOT plain manifests
(except where no good Helm chart exists).

Examples of the pattern:

- PiHole: `mojo2600.github.io/pihole-kubernetes`
- MetalLB: `metallb.github.io/metallb`
- Sealed Secrets: `bitnami-labs.github.io/sealed-secrets`

**Pattern Structure:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-name
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.example.com
    chart: chart-name
    targetRevision: x.y.z
    helm:
      valuesObject:
        # Inline values here
  destination:
    server: https://kubernetes.default.svc
    namespace: app-namespace
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Multi-Source Pattern

Some apps (like PiHole) use multi-source to combine:

1. Sealed secrets from this repo (`apps/*/manifests/`)
1. Helm chart from external repo

Example: See `apps/pihole/application.yaml`

### Secrets Management

- **Tool:** Sealed Secrets (Bitnami)
- **Controller:** `kube-system` namespace
- **Command:** `kubeseal` to encrypt secrets
- **Pattern:** Create sealed secret YAML in `apps/*/manifests/sealed-secret.yaml`
- **Sync Wave:** Use `argocd.argoproj.io/sync-wave: "-1"` to deploy secrets first

## Repository Structure

```text
homelab-gitops/
├── bootstrap/argocd/        # ArgoCD self-management
├── infrastructure/          # Core cluster services
│   └── sealed-secrets/
├── apps/                    # Applications
│   ├── home-assistant/      # Home automation platform
│   ├── metallb/             # LoadBalancer provider
│   ├── pihole/              # DNS/ad-blocking
│   ├── tplink-sync/         # TP-Link device sync job
│   └── hello-world/         # Test application
└── scripts/                 # Utility scripts
```

Each app directory contains:

- `application.yaml` - ArgoCD Application CRD (at app root)
- `manifests/` - Plain Kubernetes manifests (if needed)
- `docs/` - Application-specific documentation (optional)

## Deployed Applications

### Core Infrastructure

- **MetalLB** (v0.14.9): LoadBalancer for bare-metal - IP Pool:
  192.168.87.100-192.168.87.110, Mode: L2 Advertisement, Used by: PiHole DNS service

- **Sealed Secrets** (v2.16.2): Secret encryption for GitOps - Controller: `kube-system/sealed-secrets-controller`

### Applications

- **PiHole** (v2.34.0): DNS/ad-blocking - Web UI: `http://pihole.mosher-labs.local`,
  DNS LoadBalancer IP: `192.168.87.101`, Upstream DNS: Cloudflare (1.1.1.1, 1.0.0.1)

- **Homebridge:** removed 2026-11-26. Home Assistant replaced it, and it had no
  plugins or Apple Home pairing left. Its last config is in
  `apps/home-assistant/docs/homebridge-config-backup.json`.

- **Home Assistant** (2026.11.1): Home automation platform - LAN:
  `http://home-assistant.mosher-labs.local`, Public: `https://home.benniemosher.dev`
  (no Access gate, HA login + MFA), bjw-s app-template + cloudflared sidecar,
  HostNetwork: true pinned to hp-elitedesk, 20Gi PVC. IoT devices are on a
  separate VLAN with fixed IPs: add Kasa devices by IP. See `apps/home-assistant/RUNBOOK.md`

- **TP-Link Sync** (custom): Syncs TP-Link device names to Git - CronJob: Periodic
  sync, Python script with UniFi and GitHub integration

- **CouchDB** (chart v4.6.3 / CouchDB 3.5.1): Sync backend for the personal
  Obsidian vault (`obsidian-livesync` plugin), clusterSize: 1. No inbound
  port opened - `cloudflared` sidecar dials out to Cloudflare, gated by a
  Cloudflare Access application in front of the tunnel hostname. Admin
  credentials generated + sealed, stored in 1Password ("Mosher Home" vault,
  "CouchDB - obsidian-sync (Mosher Labs)"). See `apps/couchdb/RUNBOOK.md`
  for the Tunnel/Access setup and troubleshooting.

- **LiftTrace** (`bjw-s-labs/app-template` chart v5.2.1 /
  `ghcr.io/benniemosher/lifttrace:mosher-labs-08b2039`): Self-hosted weight
  training tracker, SQLite-backed, no telemetry. TEMPORARY custom image —
  upstream dev (1.4.0-dev04) plus our cardio public API and MCP tools, not
  merged upstream yet ([TraceApps/lifttrace#135](https://github.com/TraceApps/lifttrace/pull/135)).
  Source: `benniemosher/lifttrace`, branch `feat/cardio-public-api`, public
  GHCR package under the same account. Revert to `ghcr.io/traceapps/lifttrace`
  once #135 lands in an upstream release. Same lockdown pattern as CouchDB -
  `cloudflared` sidecar, no Service/Ingress, Cloudflare Access gates the
  tunnel hostname `lifttrace.benniemosher.dev` (with a path-scoped bypass
  for `/api/mcp` so Claude's connector can reach it — Access still gates
  everything else). `JWT_SECRET` generated + sealed
  (`apps/lifttrace/manifests/lifttrace-sealed-secret.yaml`). MCP and
  outgoing webhooks are both enabled (`MCP_ENABLED`, `WEBHOOKS_ENABLED`) —
  webhooks feed `lifttrace-strava-sync`, a separate Cloudflare Worker that
  posts completed workouts to Strava. `PUBLIC_API_ENABLED` stays off; MCP
  covers the only outside consumer so far. See `apps/lifttrace/RUNBOOK.md`
  for Tunnel/Access setup and troubleshooting.
- **Garmin MCP** (`bjw-s-labs/app-template` chart v5.3.0 /
  `ghcr.io/benniemosher/garmin-mcp:mosher-labs-0a1ab82`): MCP server that lets
  Claude read Garmin Connect data and create and schedule workouts. Upstream
  ([Taxuspt/garmin_mcp](https://github.com/Taxuspt/garmin_mcp)) publishes no
  image; `benniemosher/garmin_mcp` builds one from branch
  `local/mosher-labs-build`. Same lockdown pattern as LiftTrace, at
  `garmin.benniemosher.dev` with an Access bypass for `/mcp`, which checks
  its own bearer token (`GARMIN_MCP_HTTP_TOKEN`, sealed). Garmin OAuth tokens
  live on the PVC from a one-time `garmin-mcp-auth`; no Garmin password in
  the cluster. `delete_activity` is disabled. See `apps/garmin-mcp/RUNBOOK.md`.
- **Spotify MCP** (`bjw-s-labs/app-template` chart v5.3.0 /
  `ghcr.io/mosher-labs/spotify-mcp`): MCP server that lets Claude build
  workout playlists from Bennie's top and liked tracks, filtered by energy and
  tempo. Our own small server (`Mosher-Labs/spotify-mcp`). Tempo and energy
  come from ReccoBeats because Spotify closed audio features to new apps;
  they are cached in SQLite on the PVC. Same lockdown pattern as Garmin MCP,
  at `spotify.benniemosher.dev` with an Access bypass for `/mcp`, which checks
  its own token (`SPOTIFY_MCP_HTTP_TOKEN`, sealed, sent as `X-API-Key`). The
  Spotify refresh token lives on the PVC from a one-time `spotify-mcp-auth`
  (PKCE, no client secret). See `apps/spotify-mcp/RUNBOOK.md`.
- **tempo-service** (`bjw-s-labs/app-template` chart v5.3.0 /
  `ghcr.io/mosher-labs/tempo-service`): artist + title to BPM, from the
  iTunes 30 second preview run through Essentia, cached in SQLite on the PVC.
  Our own service (`Mosher-Labs/tempo-service`), meant as spotify-mcp's
  fallback when ReccoBeats has no tempo. No auth, so no tunnel or Ingress:
  a ClusterIP Service on 8000, and a NetworkPolicy that admits only the
  `spotify-mcp` namespace. Test with `kubectl port-forward`. One replica,
  because the iTunes rate limiter is in-process. See
  `apps/tempo-service/RUNBOOK.md`.

## Smart Home Device Context

### TP-Link Kasa Devices (IoT VLAN, 192.168.3.0/24)

All TP-Link smart plugs/switches use **port 9999** for local control. Each has a
DHCP reservation in UniFi; the full IoT IP map is in `apps/home-assistant/RUNBOOK.md`.

- Bar Lights (192.168.3.20)
- Basement Lights (192.168.3.21)
- Basement Media Lights (192.168.3.22)
- Ceiling Fan (192.168.3.23)
- Ceiling Fan Lights (192.168.3.24)
- Girl's Bathroom Fan (192.168.3.25)
- Girl's Bathroom Light (192.168.3.26)
- Hallway Lights (192.168.3.27)
- Kitchen Sink Lights (192.168.3.28)
- Office Lights (192.168.3.29)
- Patio Lights (192.168.3.30)
- Sound bar (192.168.3.31)
- Stair Lights (192.168.3.32)

**Integration Methods:**

- Home Assistant: TP-Link Kasa integration, added by IP (Kasa discovery is a
  broadcast and does not cross VLANs)

### Ring Devices

**Cameras:**

- Front Door (doorbell - cocoa_doorbell_v2)
- Side Yard South (hp_cam_v2), named Garden before 2026-11-26
- Backyard (hp_cam_v2)
- Garage (hp_cam_v1)
- Side Yard North (hp_cam_v2), named Side before 2026-11-26

**Integration:**

- Home Assistant: Ring integration (credentials + 2FA)
- Note: Ring cameras are battery-powered, use sparingly

### Rachio Sprinkler Controller

Located in garage, requires HomeKit code from physical device for pairing.

**Integration Options:**

- Rachio 3: Native HomeKit support
- Home Assistant: paired over HomeKit for local zone control, plus the Rachio
  cloud integration for rain delay, standby and schedules

### MyQ Garage Door Opener

**Status:** not integrated yet

- Chamberlain/MyQ actively blocks third-party API access
- No workaround available
- **Alternative:** Ratgdo hardware (~$30), which Home Assistant supports - Local control
  bypassing MyQ cloud, Works with Chamberlain/LiftMaster Security+ 2.0

## Development Tools & Workflows

### Required Tools

- `kubectl` - Kubernetes CLI
- `kubeseal` - Sealed Secrets encryption
- `argocd` CLI - ArgoCD management
- `gh` - GitHub CLI (for PR creation)
- `pre-commit` - Git hooks for linting

### Kubeconfig Setup

```bash
# Kubeconfig location
export KUBECONFIG=~/k3s.yaml

# Or use flag
kubectl --kubeconfig ~/k3s.yaml <command>
```

### Common Commands

```bash
# Check cluster status
kubectl --kubeconfig ~/k3s.yaml get nodes
kubectl --kubeconfig ~/k3s.yaml get pods -A

# Watch ArgoCD applications
kubectl --kubeconfig ~/k3s.yaml get applications -n argocd

# Check application logs
kubectl --kubeconfig ~/k3s.yaml logs -n <namespace> -l app=<app-name>

# Create sealed secret
kubectl create secret generic <name> \
  --from-literal=key=value \
  --dry-run=client -o yaml | \
kubeseal --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml > sealed-secret.yaml
```

### Git Workflow

**CRITICAL: ALWAYS USE PULL REQUESTS - NO EXCEPTIONS**

- NEVER commit directly to `main` branch
- NEVER push directly to `main` branch
- ALL changes MUST go through a PR, even small fixes
- This applies to Claude Code sessions as well as manual changes

**Workflow Steps:**

1. **Create feature branch:** `git checkout -b feature/description`
1. **Make changes** to code/manifests/docs
1. **ALWAYS run pre-commit BEFORE committing:** `pre-commit run --all-files` to check
   everything, Fix ALL errors (especially markdown formatting), Do NOT commit with
   `--no-verify` unless absolutely necessary
1. **Commit with conventional format:** `git commit -m "type: description"`
1. **Push and create PR:** `gh pr create --title "feat: description"`
1. **Test changes:** If your changes reference shared workflows that were also updated,
   temporarily change the reference from `@main` to `@your-branch` to test, verify
   the PR passes, then change back to `@main` before merging
1. **Merge to main:** ArgoCD automatically syncs changes

**Commit Format:** Conventional Commits (enforced by pre-commit hook)

- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `chore:` - Maintenance
- `refactor:` - Code refactoring
- `test:` - Temporary test changes (like branch references)

### Pre-commit Hooks

**Installed hooks:**

- YAML linting (yamllint)
- Markdown linting (markdownlint)
- Conventional commit format
- File hygiene (trailing whitespace, EOF, etc.)
- Checkov (security scanning)

**Setup:**

```bash
pre-commit install              # One-time setup
pre-commit run -a --all-files   # Manual run
pre-commit autoupdate           # Update hook versions
```

## ArgoCD Specifics

### Access

- UI: Configured via bootstrap (check bootstrap/argocd/values.yaml)
- CLI: `argocd login` required

### Sync Policies

All applications use:

```yaml
syncPolicy:
  automated:
    prune: true      # Delete resources removed from Git
    selfHeal: true   # Revert manual changes
  syncOptions:
    - CreateNamespace=true
```

### Sync Waves

Use annotations to control deployment order:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"  # Deploy first
```

Example: Sealed secrets deploy before apps that consume them

## Network Configuration

### Local Network

- **Homelab VLAN:** 192.168.87.0/24 (k3s nodes, MetalLB)
- **IoT VLAN:** 192.168.3.0/24 (smart devices, fixed IPs .10-.141, DHCP pool .200-.254)
- **Firewall zones (UniFi, since 2026-11-26):** IoT and Abbie each have their own zone.
  Internal (every other home network except Work) can reach both. Abbie can reach IoT, for
  casting. IoT can reach only Home Assistant (192.168.87.10:8123) on Internal. Both zones
  get the internet and only DNS, DHCP, NTP and mDNS on the gateway.
- **Main LAN (Yggdrasil):** 192.168.200.0/22
- **DNS:** PiHole at 192.168.87.101
- **Ingress Domain:** *.mosher-labs.local (Traefik)

### MetalLB Pool

- **Range:** 192.168.87.100-192.168.87.110
- **Allocated:** 192.168.87.100 (Traefik ingress), 192.168.87.101 (PiHole DNS)

### Port Notes

- **9999:** TP-Link Kasa local control protocol (used by all smart plugs)
- **8123:** Home Assistant Web UI
- **53:** DNS (PiHole)

## Important Notes

### Code Quality Standards

**CRITICAL:** All code must adhere to linter rules from the start. Do NOT write
code that needs fixing after running pre-commit hooks.

**Markdown (markdownlint):**

Configuration: `.markdownlint.yaml` (allows 2-space indent, 120 char lines)

- Nested lists under unordered items: Use 2-space indentation
- Nested lists under ordered items: Use 2-space indentation
- Inline format for simple nested items: `**Item:** Detail 1, Detail 2`
- Line length: 120 characters max (code/tables excluded)
- Bare URLs: Allowed in reference sections
- Bold for emphasis: Allowed in lists

**YAML (yamllint):**

- Maximum line length: 80 characters
- Use 2-space indentation
- No trailing whitespace
- Proper quoting for strings containing special characters
- Use `|-` for multi-line strings when appropriate

### When Working on This Repo

1. **Write linter-compliant code from the start** - Don't fix after the fact
1. **ALWAYS use OSS Helm charts** when available (check ArtifactHub)
1. **Follow the ArgoCD Application pattern** shown in existing apps
1. **Use sealed-secrets** for any credentials
1. **Test locally first** with `kubectl apply --dry-run=client`
1. **Run pre-commit hooks** BEFORE committing (fix all errors!)
1. **Create CLAUDE.md** in any new repo or sub-project
1. **Include CLAUDE.md updates in PRs** when patterns change

### Manifest Files

**IMPORTANT:** When adding plain Kubernetes manifests to `apps/*/manifests/`,
create **separate files for each resource type** due to pre-commit check-yaml rules.

**Pattern:**

- ❌ **Bad:** `deployment-and-service.yaml` (multi-document YAML)
- ✅ **Good:** `deployment.yaml` + `service.yaml` (separate files)

**Reasoning:** The `check-yaml` hook expects single-document YAML files.
While Kubernetes allows `---` separators, the linter requires separate files.

**Example:**

```text
apps/pihole/manifests/
├── sealed-secret.yaml           # One SealedSecret
├── pihole-exporter-deployment.yaml    # One Deployment
├── pihole-exporter-service.yaml       # One Service
└── pihole-exporter-servicemonitor.yaml # One ServiceMonitor
```

### Common Pitfalls

- **Don't use plain manifests** if a Helm chart exists
- **Don't commit raw secrets** - always seal them first
- **Don't skip pre-commit hooks** - they catch formatting issues
- **Remember hostNetwork: true** for apps needing mDNS (Home Assistant)
- **Check sync waves** for dependency ordering
- **Don't combine multiple resources in one YAML** - use separate files

### Home Assistant Migration Notes

- Native integrations (TP-Link, Ring, Rachio) are used; Homebridge is gone
- To show devices in Apple Home, use Home Assistant's HomeKit Bridge integration
- All HA integrations configured via UI, not YAML
- See `apps/home-assistant/docs/MIGRATION.md` for full guide

## Related Repositories

- **helm-charts:** <https://github.com/Mosher-Labs/helm-charts> - Custom Helm charts
  (currently just hello-world template)

- **ansible-node-setup:** Ansible playbooks for k3s cluster provisioning - Initial
  cluster setup, Node configuration

## References

- @README.md - Repository overview
- @apps/home-assistant/docs/MIGRATION.md - HA migration guide
- ArgoCD Docs: <https://argo-cd.readthedocs.io/>
- Sealed Secrets: <https://github.com/bitnami-labs/sealed-secrets>

---

**Last Updated:** 2025-11-14

This file should be updated whenever:

- New applications are deployed
- Architecture patterns change
- Network configuration changes
- Important context is discovered that would help future sessions
