module "datadog_alerts" {
  source = "git::https://github.com/Mosher-Labs/terraform-kubernetes-observability.git//modules/datadog?ref=df6d0072f4c462372547553a8940db1f7d5d9418" # v0.15.0

  cluster_name = "homelab"
  # The Agent (infrastructure/datadog) tags every metric kube_cluster_name:homelab.

  notifications = {
    # The workspace is connected in Datadog's Slack integration tile. Terraform
    # adds the channel.
    slack = { account_name = "Mosher_Labs", channel = "#datadog-alerts" }
    # The Heimdallr bot, as in observability-alerts. Metric monitors link
    # their graph, and service checks go to a text-only webhook.
    webex = { room_id = local.webex_room_id, token = var.webex_bot_token }
  }

  tags = ["env:homelab", "managed-by:terraform"]
}
