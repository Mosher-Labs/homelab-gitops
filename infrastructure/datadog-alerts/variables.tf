variable "datadog_api_key" {
  description = "Datadog API key, from 1Password (\"datadog api key\"). See RUNBOOK.md."
  sensitive   = true
  type        = string
}

variable "datadog_app_key" {
  description = "Datadog application key, from 1Password (\"datadog app key\"). See RUNBOOK.md."
  sensitive   = true
  type        = string
}

variable "webex_bot_token" {
  description = "Access token for the Heimdallr Webex bot, from 1Password. See RUNBOOK.md."
  sensitive   = true
  type        = string
}
