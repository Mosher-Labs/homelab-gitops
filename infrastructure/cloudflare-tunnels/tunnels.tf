# One Cloudflare Tunnel per entry in local.tunnel_apps. Each tunnel is
# "remotely configured" (config_src = "cloudflare") — the ingress rules
# live in Cloudflare's control plane via cloudflare_zero_trust_tunnel_cloudflared_config
# below, not a local config.yml on the origin. The connector container
# (cloudflared) just runs `tunnel run --token <token>` with no other
# config, which is what the token in the tunnel_tokens output is for.

resource "random_id" "tunnel_secret" {
  for_each    = local.tunnel_apps
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "apps" {
  for_each = local.tunnel_apps

  account_id    = var.cloudflare_account_id
  name          = each.key
  config_src    = "cloudflare"
  tunnel_secret = random_id.tunnel_secret[each.key].b64_std
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "apps" {
  for_each = local.tunnel_apps

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.apps[each.key].id

  config = {
    ingress = [
      {
        hostname = "${each.value.subdomain}.${each.value.zone}"
        service  = each.value.service
      },
      # Required catch-all — a tunnel config's last ingress rule must have
      # no hostname.
      {
        service = "http_status:404"
      }
    ]
  }
}

# Computes the same base64 connector token `cloudflared tunnel run --token`
# expects, from the tunnel_secret we generated above — this is what makes
# the whole tunnel provisionable without ever opening the Zero Trust
# dashboard.
data "cloudflare_zero_trust_tunnel_cloudflared_token" "apps" {
  for_each = local.tunnel_apps

  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.apps[each.key].id
}

resource "cloudflare_dns_record" "tunnel_apps" {
  for_each = local.tunnel_apps

  zone_id = data.cloudflare_zone.zones[each.value.zone].zone_id
  name    = "${each.value.subdomain}.${each.value.zone}"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.apps[each.key].id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}
