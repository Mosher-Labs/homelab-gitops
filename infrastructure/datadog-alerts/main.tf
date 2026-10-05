module "datadog_alerts" {
  source = "git::https://github.com/Mosher-Labs/terraform-kubernetes-observability.git//modules/datadog?ref=0ee4a1023a8b64f62ec301b9edc7278e195341f3" # v0.13.5

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
