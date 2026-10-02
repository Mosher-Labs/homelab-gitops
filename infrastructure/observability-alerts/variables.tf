variable "grafana_auth" {
  description = "Grafana credentials as \"user:password\", read from the monitoring/grafana-admin Secret. See RUNBOOK.md."
  type        = string
  sensitive   = true
}

variable "grafana_url" {
  description = "URL of the homelab Grafana."
  type        = string
  default     = "http://grafana.mosher-labs.local"
}

variable "slack" {
  description = "Slack bot token and channel ID for alerts, from 1Password. Null keeps notifications off. See RUNBOOK.md."
  type = object({
    token     = string
    recipient = string
  })
  default   = null
  sensitive = true
}
