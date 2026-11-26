# RUNBOOK.md - home-assistant

## Overview

Home Assistant runs every smart-home device and automation in one place. It
runs on the `bjw-s-labs/app-template` chart with a `cloudflared` sidecar, the
same pattern as `apps/garmin-mcp`.

- **Namespace:** `home-assistant`
- **LAN URL:** `http://home-assistant.mosher-labs.local` or
  `http://192.168.87.10:8123`
- **Public URL:** `https://home.benniemosher.dev`
- **Node:** pinned to `hp-elitedesk`. The chart creates the 20Gi
  `local-path` config volume there on first sync, and local-path keeps it on
  that node.
- **Networking:** `hostNetwork: true`. Home Assistant uses the node's
  homelab-VLAN address. The IoT VLAN has its own UniFi firewall zone. The
  homelab VLAN can reach it. The IoT VLAN can reach only Home Assistant on port 8123 (so Google Cast devices can
  fetch announcement audio), so otherwise only integrations where Home
  Assistant opens the connection work. UniFi reflects mDNS between the VLANs,
  so Cast and HomeKit devices are discovered. Broadcast discovery (Kasa) does
  not cross: add those devices by IP.
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

Every IoT device has a DHCP reservation in UniFi. Add Kasa devices by IP in the
integration's setup dialog; Cast and HomeKit devices show up through mDNS.

| IP (192.168.3.x) | Device |
| --- | --- |
| .10, .11 | Ring Chime Pro (two MACs) |
| .20 | Bar Lights |
| .21 | Basement Lights |
| .22 | Basement Media Lights |
| .23 | Ceiling Fan |
| .24 | Ceiling Fan Lights |
| .25 | Girl's Bathroom Fan |
| .26 | Girl's Bathroom Light |
| .27 | Hallway Lights |
| .28 | Kitchen Sink Lights |
| .29 | Office Lights |
| .30 | Patio Lights |
| .31 | Sound bar (plug) |
| .32 | Stair Lights |
| .60 | Backyard Speaker (Google Home Mini) |
| .61 | Basement Speaker |
| .62 | Girl's Bathroom Speaker |
| .63 | Kitchen Speaker |
| .64 | Master Bedroom Speaker |
| .80-.82 | Living Room, Maisie's Room, Master Bedroom TVs (Ethernet) |
| .83 | Basement TV (LG, Ethernet) |
| .90-.92 | Same TVs as .80-.82 (Wi-Fi) |
| .93 | Basement TV (LG, Wi-Fi) |
| .100 | Ring Doorbell |
| .101-.102 | Backyard and Garage cameras (Ring) |
| .103 | Side Yard South camera (Ring) |
| .104 | Side Yard North camera (Ring) |
| .110 | Garage Door (MyQ) |
| .120 | Thermostat (Ecobee) |
| .121 | Sprinklers (Rachio) |
| .140 | Samsung Refrigerator |
| .141 | Mr. Clean (Wyze vacuum) |

The DHCP pool is .200-.254, so a new device lands there until it gets a reservation.

## Community integrations

The `custom-components` init container installs community integrations into
`/config/custom_components` before Home Assistant starts. Each one is pinned
in `application.yaml` to a release tag and the commit that tag points to, and
the container refuses to install it if the two disagree. HACS is not used.
Renovate bumps the tag and the commit together.

Installed now:

- `simple_wyze_vac` ([romedtino/simple-wyze-vac](https://github.com/romedtino/simple-wyze-vac)),
  for the Wyze vacuum. It needs a Wyze API key ID and key from
  <https://developer-api-console.wyze.com>, entered when you add the
  integration. Cloud only.

To add another, add a `_VERSION` and `_COMMIT` env pair under a
`# renovate:` comment and one more `install` line.

## Rooms and names (layout.yaml)

`layout/layout.yaml` holds the floors, the areas, and each device's name and
room, matched by MAC address or integration ID. It also holds each entity's
ID, matched by domain, platform and unique ID. It has no secrets. After
changing rooms or names in the UI, export it and commit the result:

```bash
cd apps/home-assistant/layout
uv run --with websockets==15.0.1 --with pyyaml==6.0.3 ha_layout.py export
```

To put a rebuilt Home Assistant back the way it was, pair the devices, then:

```bash
uv run --with websockets==15.0.1 --with pyyaml==6.0.3 ha_layout.py apply          # dry run
uv run --with websockets==15.0.1 --with pyyaml==6.0.3 ha_layout.py apply --apply
```

Both read a long-lived token from `~/.config/ha/token`.

## Backups

Home Assistant makes its own encrypted backups on the schedule under
Settings > System > Backups (daily, keep 7, local). The encryption key is in
1Password; without it a backup cannot be restored.

The `backup-copy` CronJob runs at 06:30 on battlestation. It downloads any new
backup over Home Assistant's API into `/data/backups/home-assistant` and keeps
the newest 14. It fails, and so shows as a failed job, when a backup is not
encrypted or the newest one is more than 36 hours old. Its token is the
long-lived token named "backup-copy (homelab-gitops CronJob)" in Home
Assistant's admin profile, sealed in `backup-copy-sealed-secret.yaml`.

The folder must exist before the first run, owned by uid 1000:

```bash
mkdir -p /data/backups/home-assistant   # on battlestation, as benniemosher
```

Check it:

```bash
kubectl -n home-assistant get jobs -l batch.kubernetes.io/cronjob-name=backup-copy
ls -lh /data/backups/home-assistant
```

Run it now: `kubectl -n home-assistant create job --from=cronjob/backup-copy backup-copy-manual`.

### Restoring after losing hp-elitedesk

1. Let ArgoCD deploy Home Assistant on its new node. Change the
   `nodeSelector` first if hp-elitedesk is gone.
2. On the onboarding screen, choose to restore from a backup, upload the
   newest file from `/data/backups/home-assistant`, and enter the encryption
   key from 1Password.
3. If no backup survived, set Home Assistant up fresh, add the integrations
   again, pair the HomeKit and Android TV devices, and run
   `ha_layout.py apply --apply` to put every device back in its room.

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
