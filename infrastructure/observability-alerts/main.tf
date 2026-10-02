module "observability" {
  source = "git::https://github.com/Mosher-Labs/terraform-kubernetes-observability.git?ref=7f33f9ef5bb8ab264cd65768c06f542af68e72ab" # v0.1.0

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
