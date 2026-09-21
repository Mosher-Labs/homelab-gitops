output "tunnel_tokens" {
  description = <<-EOT
    Per-app cloudflared connector tokens, keyed by the same key as
    local.tunnel_apps. Sensitive — never commit the raw value. Retrieve
    with `terraform output -json tunnel_tokens`, then seal it into the
    target app's namespace as the `cloudflared-credentials` secret's
    `tunnel-token` key (see e.g. apps/<app>/RUNBOOK.md).
  EOT
  value       = { for k, v in data.cloudflare_zero_trust_tunnel_cloudflared_token.apps : k => v.token }
  sensitive   = true
}
