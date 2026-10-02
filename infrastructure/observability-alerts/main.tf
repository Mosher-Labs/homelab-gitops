module "observability" {
  source = "git::https://github.com/Mosher-Labs/terraform-kubernetes-observability.git?ref=add08c0318aea607e201078f43664275df637ebb" # v0.4.0

  cluster_name = "homelab"
  cluster_type = "k3s"
  dashboards = {
    # Adds an error-logs panel from infrastructure/loki.
    loki_datasource_uid = "loki"
  }
  # Slack is on when TF_VAR_slack is set; see RUNBOOK.md.
  notifications = {
    enabled = nonsensitive(var.slack != null)
  }
  prometheus_datasource_uid = "prometheus"
  slack = var.slack == null ? null : {
    recipient = var.slack.recipient
    token     = var.slack.token
    # Grafana posts as "Grafana" unless told otherwise.
    username = "Heimdallr"
  }
}
