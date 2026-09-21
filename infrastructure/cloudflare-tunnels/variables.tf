variable "cloudflare_api_token" {
  description = "Cloudflare API token, scoped to Zone:Read, DNS:Edit, Cloudflare Tunnel:Edit, Access: Apps and Policies:Edit on the target zone(s). Sourced from 1Password — see RUNBOOK.md."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the zone(s) referenced in local.tunnel_apps. Sourced from 1Password — see RUNBOOK.md."
  type        = string
  sensitive   = true
}

variable "allowed_emails" {
  description = "Emails allowed through the shared Access policy applied to every app in local.tunnel_apps. Sourced from 1Password — see RUNBOOK.md."
  type        = list(string)
  sensitive   = true
}
