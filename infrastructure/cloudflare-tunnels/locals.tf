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
      # Paths that get their own no-auth-at-Access-layer Application
      # (see access.tf's bypass policy) instead of inheriting the
      # personal-allow login gate. Only for paths with their own real
      # auth — /api/mcp requires a per-token mcp:read/write/destroy
      # bearer token regardless, checked by the app itself. Needed
      # because Access has no concept of "let a non-interactive
      # bearer-token client through" — an external caller with no
      # human to click through a login page (Claude's MCP connector
      # probe, in this case) just sees Access's redirect and fails,
      # even with a perfectly valid app-level token.
      access_bypass_paths = ["/api/mcp"]
    }
  }

  zone_names = toset([for app in local.tunnel_apps : app.zone])

  # Flatten (app, path) pairs across every tunnel_app's
  # access_bypass_paths into one map keyed by "<app>|<path>", for a
  # single for_each in access.tf.
  bypass_targets = merge([
    for app_key, app in local.tunnel_apps : {
      for path in try(app.access_bypass_paths, []) :
      "${app_key}|${path}" => {
        app_key   = app_key
        zone      = app.zone
        subdomain = app.subdomain
        path      = path
      }
    }
  ]...)
}
