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

variable "healthchecksio_api_key" {
  description = "Read-write healthchecks.io API key for the project that holds the heartbeat check, from 1Password. See RUNBOOK.md."
  sensitive   = true
  type        = string
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

variable "webex_bot_token" {
  default     = null
  description = "Access token for the Heimdallr Webex bot, from 1Password. Takes precedence over webex_webhook_url. See RUNBOOK.md."
  sensitive   = true
  type        = string
}

variable "webex_webhook_url" {
  default     = null
  description = "Webex incoming webhook URL, from 1Password: the fallback when webex_bot_token is unset. See RUNBOOK.md."
  sensitive   = true
  type        = string
}
