locals {
  # Self-hosted apps exposed to the internet via a dedicated Cloudflare
  # Tunnel each — one cloudflared sidecar per app pod in this cluster, no
  # inbound port ever opened. Add an entry here instead of clicking
  # through the Zero Trust dashboard; see tunnels.tf/access.tf for what
  # gets provisioned per entry. `zone` must be a zone already managed in
  # the separate `cloudflare-management` repo — this stack only reads it
  # (see data.tf), it doesn't own zone creation.
  tunnel_apps = {
    lifttrace = {
      zone      = "benniemosher.dev"
      subdomain = "lifttrace"
      # cloudflared talks to the app over loopback inside the shared pod.
      service = "http://localhost:3002"
    }
  }

  zone_names = toset([for app in local.tunnel_apps : app.zone])
}
