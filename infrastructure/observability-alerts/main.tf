module "observability" {
  # TEMPORARY: pinned to the head of Mosher-Labs/terraform-kubernetes-observability#1
  # until it merges and releases v0.1.0.
  source = "git::https://github.com/Mosher-Labs/terraform-kubernetes-observability.git?ref=9d7764f242623384055856194d1315a8cf5401ce"

  cluster_name              = "homelab"
  cluster_type              = "k3s"
  prometheus_datasource_uid = "prometheus"

  # Notifications stay off until the Slack token is in 1Password.
  notifications = {
    enabled = nonsensitive(var.slack != null)
  }
  slack = var.slack == null ? null : {
    token     = var.slack.token
    recipient = var.slack.recipient
    username  = "Grafana"
  }
}
