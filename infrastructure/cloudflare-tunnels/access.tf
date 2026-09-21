# A single reusable Access policy — "allow these emails" — applied to
# every app in local.tunnel_apps. All of these are personal, single-user
# apps behind the tunnels in tunnels.tf, so one shared policy is enough;
# split per-app if an app ever needs a different audience.
resource "cloudflare_zero_trust_access_policy" "personal" {
  account_id = var.cloudflare_account_id
  name       = "personal-allow"
  decision   = "allow"

  include = [
    for email in var.allowed_emails : {
      email = { email = email }
    }
  ]
}

resource "cloudflare_zero_trust_access_application" "tunnel_apps" {
  for_each = local.tunnel_apps

  account_id       = var.cloudflare_account_id
  name             = each.key
  domain           = "${each.value.subdomain}.${each.value.zone}"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [
    { id = cloudflare_zero_trust_access_policy.personal.id }
  ]
}

# No-auth-at-Access-layer policy for local.bypass_targets paths — the
# request passes straight through to origin, where the app's own
# token/bearer auth is the real gate. `include` is set to "everyone"
# purely because the API still expects an include block even though a
# bypass decision makes it a no-op.
resource "cloudflare_zero_trust_access_policy" "bypass" {
  account_id = var.cloudflare_account_id
  name       = "bypass-all"
  decision   = "bypass"

  include = [
    { everyone = {} }
  ]
}

# A more specific path match wins over the app-level Application above
# for the same hostname — this is what actually carves /api/mcp (etc.)
# out from under the personal-allow login gate.
resource "cloudflare_zero_trust_access_application" "bypass_paths" {
  for_each = local.bypass_targets

  account_id       = var.cloudflare_account_id
  name             = "${each.value.app_key}-bypass-${replace(each.value.path, "/", "-")}"
  domain           = "${each.value.subdomain}.${each.value.zone}${each.value.path}"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [
    { id = cloudflare_zero_trust_access_policy.bypass.id }
  ]
}
