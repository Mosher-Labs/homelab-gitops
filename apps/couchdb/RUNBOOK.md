# RUNBOOK.md - couchdb

## Overview

Self-hosted CouchDB backing `obsidian-livesync` for the personal Obsidian
vault. Single node (this is single-user, not a real multi-writer workload).
No inbound port is ever opened on the homelab network — the only path in is
a `cloudflared` sidecar making an *outbound* connection to Cloudflare's
edge, same pattern as `apps/book-review-publisher`.

- **Namespace:** `couchdb`
- **Internal URL:** not reachable from other pods — see the NetworkPolicy
  note below
- **Public URL:** `https://obsidian-sync.benniemosher.dev` (adjust to your
  actual zone)
- **Chart:** `apache/couchdb-helm` v4.6.3 (CouchDB 3.5.1)
- **Admin credentials:** 1Password → "Mosher Home" vault → "CouchDB -
  obsidian-sync (Mosher Labs)"

## Why this is locked down the way it is

- **No public IP/port at all.** `cloudflared` only dials *out* to
  Cloudflare. There is nothing listening on the homelab's router/firewall
  for this service — an attacker can't port-scan or flood an origin they
  can't address. This is the actual DDoS defense, not a WAF rule.
- **Cloudflare Access in front of the tunnel hostname.** Even someone who
  discovers the hostname can't reach CouchDB without passing an Access
  policy first (see step 2).
- **CouchDB itself also refuses anonymous requests**
  (`require_valid_user: true` on both `chttpd` and `chttpd_auth`) —
  defense in depth in case Access or the tunnel is ever misconfigured.
- **NetworkPolicy denies all ingress to the CouchDB pod** from anything
  else in the cluster. `cloudflared` reaches CouchDB over
  `127.0.0.1:5984` inside the same pod, which bypasses Service networking
  and isn't affected by the policy — nothing else needs a path in.
- **Admin credentials were generated randomly and sealed** — see
  `manifests/admin-sealed-secret.yaml`, already committed and safe (only
  this cluster's private key can decrypt it).

## Initial deployment

### 1. Create the Cloudflare Tunnel

In the Cloudflare Zero Trust dashboard → Networks → Tunnels:

1. Create a tunnel named `couchdb` (or `obsidian-sync`), connector type
   **Cloudflare**.
1. Copy the tunnel token shown during setup — you'll seal it in step 3.
1. Under **Public Hostname**, add:
   - Subdomain: `obsidian-sync`, domain: your zone (e.g.
     `benniemosher.dev`)
   - Service: `HTTP` → `localhost:5984` (cloudflared talks to CouchDB
     over loopback inside the pod, so from cloudflared's point of view
     CouchDB is always local)

### 2. Create a Cloudflare Access application

In Zero Trust → Access → Applications → Add an application →
**Self-hosted**:

1. Application domain: the same `obsidian-sync.<zone>` hostname from
   step 1.
1. Policy: Allow, include rule = your email (Emails) — add a second
   identity here only if another device/person genuinely needs sync
   access.
1. Session duration: short-lived (e.g. 24h) is fine —
   `obsidian-livesync` re-authenticates transparently against CouchDB's
   own auth, this Access session just gates the tunnel hostname itself.
1. Under the zone's **Security → Bots**, enable **Bot Fight Mode**
   (free) and add a rate-limiting rule on the `obsidian-sync.<zone>`
   hostname if you want extra headroom beyond what Access already
   blocks.

### 3. Seal the tunnel token

```bash
kubectl create secret generic cloudflared-credentials \
  --namespace couchdb \
  --from-literal=tunnel-token=YOUR_TUNNEL_TOKEN_HERE \
  --dry-run=client -o yaml | \
kubeseal \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml \
  > apps/couchdb/manifests/cloudflared-sealed-secret.yaml
```

Commit `manifests/cloudflared-sealed-secret.yaml` — it's safe to store in
git, same as the admin credentials.

### 4. Merge this PR

ArgoCD syncs automatically once merged to `main`.

### 5. Verify deployment

```bash
kubectl get pods -n couchdb
kubectl logs -n couchdb -l app=couchdb -c couchdb
kubectl logs -n couchdb -l app=couchdb -c cloudflared
curl -u <username>:<password> https://obsidian-sync.<zone>/_up
```

(The `curl` will prompt for the Access login flow first if hit from a
browser; from the CLI you'll need a service token or to test from a
browser session instead.)

### 6. Connect obsidian-livesync

On desktop first, then mobile:

1. Install the `obsidian-livesync` community plugin.
1. Point it at `https://obsidian-sync.<zone>` with the username/password
   from the 1Password item.
1. Set an **end-to-end encryption passphrase** — this is separate from
   the CouchDB password above and is never stored in 1Password by this
   runbook; generate and store it yourself, since it encrypts note
   content client-side before it ever reaches CouchDB.
1. Use the plugin's built-in "Check and Fix CouchDB configuration"
   wizard once connected — it verifies CORS/auth settings match what the
   plugin needs and can patch minor mismatches live.
1. Test sync with a throwaway note before trusting it with real data.

## Backups

The PVC is the only copy of vault history that isn't also sitting on
every synced device — losing it isn't catastrophic (devices still have
full copies) but it does lose CouchDB's revision history/conflict log.
Two low-effort options, pick one:

- **Simplest:** rely on the PVC's underlying storage already being
  durable (NFS-backed Drobo, per the cluster's storage setup) rather
  than node-local disk.
- **Better:** add a CronJob running `couchbackup`
  (`@cloudant/couchbackup` on npm) against
  `http://<user>:<pass>@localhost:5984/obsidian` on a schedule, writing
  the dump to the NFS share. Not included here — add it if/when the
  vault's history is something you'd actually restore from, rather than
  speculatively.

## Rotating the admin password

1. Generate a new password, seal a new
   `manifests/admin-sealed-secret.yaml` with the same four keys
   (`adminUsername`, `adminPassword`, `cookieAuthSecret`,
   `erlangCookie` — keep the latter two unchanged unless you're
   rotating everything, changing `erlangCookie` on a running
   single-node cluster is harmless but pointless).
1. Update the 1Password item.
1. Update the password in `obsidian-livesync` settings on every device
   *before* merging — the pod will restart with the new password on
   sync and old sessions will start failing auth immediately.

## Troubleshooting

### Pod not starting / cloudflared crashlooping

```bash
kubectl describe pod -n couchdb -l app=couchdb
```

Common cause: `cloudflared-credentials` sealed secret not created yet
(step 3) — CouchDB itself will still be `Running`, only the
`cloudflared` container restarts.

### Devices can't reach the hostname at all

Check the Access application's policy actually includes the identity
you're logging in with, and that the tunnel's Public Hostname config
points at `localhost:5984` (not a Service DNS name — cloudflared is in
the same pod, it should never need to resolve a Kubernetes Service).

### Sync works on one device but not another

Re-run the plugin's "Check and Fix CouchDB configuration" wizard on the
failing device — this is almost always a CORS origin mismatch for that
platform.
