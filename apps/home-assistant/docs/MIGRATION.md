# Migrating from Standalone Homebridge to Home Assistant

This guide walks through deploying Home Assistant to the Kubernetes cluster
and migrating Homebridge to run as a Home Assistant add-on.

## Overview

**Why Home Assistant?**

- Platform-agnostic home automation (works with Apple, Google, Alexa, etc.)
- Single dashboard for all devices
- Unified camera view with live feeds
- Local-first control (no cloud dependencies required)
- Powerful automation engine
- Can run Homebridge as an add-on to maintain HomeKit support

## Deployment Steps

### 1. Deploy Home Assistant

The Home Assistant deployment is managed by ArgoCD and will automatically
sync once merged to the `main` branch.

**Components:**

- Namespace: `home-assistant`
- Persistent Volume: 20Gi (for database, recordings, and add-ons)
- Access: `http://home-assistant.mosher-labs.local`
- Resource limits: 1 CPU / 2Gi RAM

**Configuration:**

- Uses `hostNetwork: true` for local device discovery (mDNS, Bonjour)
- Privileged container for USB/Bluetooth device access
- Timezone: America/Denver

### 2. Initial Home Assistant Setup

Once deployed, access Home Assistant at
`http://home-assistant.mosher-labs.local`:

1. **Create an account** - First user becomes the admin
1. **Set your location** - For accurate sun/weather automations
1. **Skip integrations** for now - We'll add them manually

### 3. Add Native Home Assistant Integrations

Home Assistant has built-in integrations that work better than
Homebridge plugins:

#### TP-Link Kasa Integration

1. Navigate to **Settings → Devices & Services**
1. Click **Add Integration**
1. Search for "TP-Link Kasa Smart"
1. **Auto-discovery** should find all your devices on `192.168.3.x`
1. Alternatively, manually add each device IP if needed

**Devices that will be discovered:**

- Stair Lights (192.168.3.125)
- Ceiling Fan Light (192.168.3.229)
- Basement Media Lights (192.168.3.225)
- Bar Lights (192.168.3.134)
- Sound bar (192.168.3.26)
- Basement Lights (192.168.3.195)
- Office Lights (192.168.3.25)
- Ceiling Fan (192.168.3.44)
- Patio Lights (192.168.3.138)
- Hallway Lights (192.168.3.140)
- Plus 3 more devices

#### Ring Integration

1. Navigate to **Settings → Devices & Services**
1. Click **Add Integration**
1. Search for "Ring"
1. Enter your Ring credentials (same as iOS app)
1. Complete 2FA if prompted

**Devices that will be configured:**

- Front Door (doorbell)
- Garden camera
- Backyard camera
- Garage camera
- Side camera
- All associated sensors (motion, battery, etc.)

**Note:** You'll need to re-authenticate Ring credentials. The refresh
token from Homebridge is not transferable.

#### Rachio Integration

1. Navigate to **Settings → Devices & Services**
1. Click **Add Integration**
1. Search for "Rachio"
1. Enter your Rachio credentials

### 4. Install Homebridge Add-on (Optional)

If you want to maintain HomeKit support alongside Home Assistant:

#### Install the Homebridge Add-on

1. Navigate to **Settings → Add-ons → Add-on Store**
1. Click the three dots (⋮) in the top right
1. Select **Repositories**
1. Add: `https://github.com/hassio-addons/repository`
1. Refresh the page
1. Search for "Homebridge"
1. Click **Install**

#### Configure Homebridge Add-on

1. Go to the **Configuration** tab
1. You can either:
   - **Option A:** Start fresh with auto-discovered HA devices
   - **Option B:** Import existing Homebridge config (see below)

#### Import Existing Homebridge Configuration

The backup config is saved in `docs/homebridge-config-backup.json`.

**Important notes:**

- The **Bridge credentials** (PIN: 764-66-872) can be reused
- You'll need to **remove the Ring platform** (HA integration handles this)
- You'll need to **remove the TP-Link platform**
  (HA integration handles this)
- The Homebridge add-on will expose **HA entities to HomeKit** instead

**Simplified config for the Homebridge add-on:**

```json
{
    "bridge": {
        "name": "Homebridge 3D65",
        "username": "0E:4E:74:DB:3D:65",
        "port": 51826,
        "pin": "764-66-872"
    },
    "accessories": [],
    "platforms": [
        {
            "name": "Config",
            "port": 8581,
            "platform": "config"
        }
    ]
}
```

The Homebridge add-on automatically discovers Home Assistant entities
and exposes them to HomeKit.

#### Start Homebridge Add-on

1. Go to the **Info** tab
1. Click **Start**
1. Enable **Start on boot** and **Watchdog**
1. Check the **Log** tab to verify it's running

### 5. Verify Device Access

#### Home Assistant Dashboard

1. Navigate to **Overview** in the sidebar
1. You should see all your devices from TP-Link, Ring, and Rachio
1. Test controlling a few devices

#### HomeKit (if using Homebridge add-on)

1. Open the **Home app** on iOS
1. Your existing HomeKit setup should still work
1. The bridge name and PIN remain the same
1. All devices are now sourced from Home Assistant instead of
   direct plugins

### 6. Set Up Camera Dashboard

One of the main benefits of Home Assistant is the unified camera view:

1. Navigate to **Overview**
1. Click the three dots (⋮) → **Edit Dashboard**
1. Click **Add Card** → **Picture Glance**
1. Select your Ring cameras
1. Enable **Live View**
1. Repeat for all cameras
1. You can create a dedicated **Camera** dashboard view

### 7. Remove Standalone Homebridge (Once Stable)

After verifying everything works in Home Assistant:

1. **Delete the ArgoCD Application:**

   ```bash
   kubectl delete application homebridge -n argocd
   ```

1. **Remove the Homebridge deployment:**

   ```bash
   kubectl delete namespace homebridge
   ```

1. **Remove from Git:**
   - Delete `apps/homebridge/` directory
   - Commit and push changes

## Integration Credentials Reference

### Ring

- **Username:** Your Ring account email
- **Password:** Your Ring account password
- **2FA:** May be required during initial setup

### TP-Link Kasa

- **No credentials needed** - Uses local discovery on the network
- Devices communicate directly via local IP addresses

### Rachio

- **Username:** Your Rachio account email
- **Password:** Your Rachio account password

## Troubleshooting

### Devices Not Discovered

If TP-Link devices aren't auto-discovered:

1. Verify Home Assistant pod is using `hostNetwork: true`
1. Check devices are reachable:
   `kubectl exec -n home-assistant <pod> -- ping 192.168.3.125`
1. Manually add integration with device IP addresses

### Ring Authentication Issues

If Ring login fails:

1. Ensure 2FA is completed
1. Try logging out and back in from the Ring iOS app
1. Check for Ring service outages
1. Review Home Assistant logs: `kubectl logs -n home-assistant <pod>`

### Homebridge Add-on Issues

If the Homebridge add-on doesn't start:

1. Check add-on logs in Home Assistant UI
1. Verify the config.json syntax is valid
1. Remove any incompatible platforms from the config
1. Try starting with the minimal config shown above

### Camera Streams Not Loading

If Ring camera live streams don't work:

1. This is expected - Ring cameras require their servers
1. Home Assistant shows snapshots and recorded events
1. For live streaming, use the Ring app or consider local cameras

## Next Steps

Once Home Assistant is stable:

1. **Explore Automations** - Go to Settings → Automations & Scenes
1. **Create Dashboards** - Customize your views
1. **Add More Integrations** - Weather, calendar, media players, etc.
1. **Set Up HTTPS** - For secure remote access (optional)
1. **Configure Backups** - Use Home Assistant's built-in backup feature

## Rollback Plan

If you need to roll back to standalone Homebridge:

1. The standalone Homebridge namespace and deployment still exist
1. Simply revert the changes in Git
1. ArgoCD will restore the previous state
1. Your Homebridge config is backed up in the PVC

---

**Questions or Issues?**

Check the Home Assistant logs:

```bash
kubectl logs -n home-assistant -l app=home-assistant --tail=100 -f
```

Review the deployment status:

```bash
kubectl get pods -n home-assistant
kubectl describe pod -n home-assistant <pod-name>
```
