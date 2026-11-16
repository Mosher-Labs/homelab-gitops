# RUNBOOK.md - home-assistant

## Overview

Home Assistant runs every smart-home device and automation in one place. It
runs on the `bjw-s-labs/app-template` chart with a `cloudflared` sidecar, the
same pattern as `apps/garmin-mcp`.

- **Namespace:** `home-assistant`
- **LAN URL:** `http://home-assistant.mosher-labs.local` or
  `http://192.168.87.10:8123`
- **Public URL:** `https://home.benniemosher.dev`
- **Node:** pinned to `hp-elitedesk`, where the `home-assistant-config`
  local-path volume lives.
- **Networking:** `hostNetwork: true`. Home Assistant uses the node's
  homelab-VLAN address. The homelab VLAN can reach the IoT VLAN, but the IoT
  VLAN cannot reach back, so only integrations where Home Assistant opens the
  connection work. Discovery (mDNS, SSDP) does not cross VLANs: add IoT
  devices by IP.
- **Auth:** Home Assistant's own login. The hostname has no Cloudflare Access
  gate, because the iPhone app cannot complete an Access login. Turn on MFA
  for every user.
- **Proxy trust:** an init container appends an `http:` block to
  `configuration.yaml` that trusts `127.0.0.1` (cloudflared) and
  `10.42.0.0/16` (Traefik). It only runs when there is no `http:` block yet.

## Initial deployment

### 1. Provision the tunnel

`home-assistant` is an entry in `infrastructure/cloudflare-tunnels/locals.tf`
with `access_enabled = false`. Apply that stack as its RUNBOOK describes.
Expect a tunnel, its config and a DNS record to be added, and no Access
application.

### 2. Seal the tunnel token

```bash
cd infrastructure/cloudflare-tunnels
terraform output -json tunnel_tokens | jq -j '."home-assistant"' |
  kubectl create secret generic cloudflared-credentials \
    --namespace home-assistant --from-file=tunnel-token=/dev/stdin \
    --dry-run=client -o yaml |
  kubeseal --controller-namespace kube-system \
    --controller-name sealed-secrets-controller --format yaml \
    > ../../apps/home-assistant/manifests/cloudflared-sealed-secret.yaml
```

Commit it to the PR. Until it exists, `cloudflared` crashloops and the pod is
never Ready, so the LAN ingress has no endpoint either.

### 3. Merge

ArgoCD syncs `apps/home-assistant/application.yaml`.

### 4. Onboard

Open the LAN URL and create the owner account. Then, in your profile, turn on
multi-factor authentication before using the public URL.

In Settings → System → Network, set:

- Home Assistant URL, Internet: `https://home.benniemosher.dev`
- Home Assistant URL, Local network: `http://192.168.87.10:8123`

### 5. Install the iPhone app

Install Home Assistant from the App Store and sign in with the public URL.
Allow location "Always" and Motion & Fitness, so the app reports zones and
the Activity sensor that run automations use.

## Adding IoT devices

Add each IoT-VLAN device by IP in its integration's setup dialog.
Auto-discovery only sees the homelab VLAN.

## Upgrading

Renovate opens image updates. Read the release notes for breaking changes
before merging; Home Assistant migrates its database on first start, and
the old version cannot read it afterwards.

## Troubleshooting

### 400 Bad Request through the public URL

The `http:` block is missing or does not trust the proxy. Check the top of
`/config/configuration.yaml`:

```bash
kubectl exec -n home-assistant deploy/home-assistant -c app -- \
  grep -A6 '^http:' /config/configuration.yaml
```

### An IoT device goes unavailable

Check it still has the IP Home Assistant was given. Reserve IoT addresses in
DHCP.
