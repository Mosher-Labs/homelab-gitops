module "observability" {
  source = "git::https://github.com/Mosher-Labs/terraform-kubernetes-observability.git?ref=a9d0ca931dbe67fda842f2dbb23d495554e6130d" # v0.2.0

  cluster_name = "homelab"
  cluster_type = "k3s"
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
