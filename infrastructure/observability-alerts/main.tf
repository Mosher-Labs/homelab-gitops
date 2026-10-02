module "observability" {
  source = "git::https://github.com/Mosher-Labs/terraform-kubernetes-observability.git?ref=85722d2fd5b9276ce7770614676ea8d776bed71d" # v0.6.0

  cluster_name = "homelab"
  cluster_type = "k3s"
  dashboards = {
    # Adds an error-logs panel from infrastructure/loki.
    loki_datasource_uid = "loki"
  }
  # Each channel is on when its TF_VAR_ is set; see RUNBOOK.md.
  notifications = {
    enabled = nonsensitive(var.slack != null || var.webex_webhook_url != null)
    # Heimdallr's logo. Shows on Slack; Webex needs a bot for an avatar.
    icon_url = "https://avatars.githubusercontent.com/u/195353313?v=4"
  }
  prometheus_datasource_uid = "prometheus"
  slack = var.slack == null ? null : {
    recipient = var.slack.recipient
    token     = var.slack.token
    # Grafana posts as "Grafana" unless told otherwise.
    username = "Heimdallr"
  }
  webex = var.webex_webhook_url == null ? null : {
    webhook_url = var.webex_webhook_url
  }
}
