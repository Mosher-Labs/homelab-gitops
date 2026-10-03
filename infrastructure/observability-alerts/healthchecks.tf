# The outside half of the alerting heartbeat (see RUNBOOK.md). Grafana pings
# this check every 5 minutes for as long as it can query Prometheus; when the
# pings stop, healthchecks.io alerts every channel below.
#
# healthchecks.io's API can't create integrations, so each channel is added
# once in its web UI and looked up here by kind (and name, for the webhook).

data "healthchecksio_channel" "email" {
  kind = "email"
}

data "healthchecksio_channel" "slack" {
  kind = "slack"
}

# A generic webhook that posts to the Webex incoming webhook. healthchecks.io
# has no Webex integration of its own.
data "healthchecksio_channel" "webex" {
  kind = "webhook"
  name = "Webex"
}

resource "healthchecksio_check" "heartbeat" {
  channels = [
    data.healthchecksio_channel.email.id,
    data.healthchecksio_channel.slack.id,
    data.healthchecksio_channel.webex.id,
  ]
  desc    = "Grafana pings this every 5 minutes while it can query Prometheus (infrastructure/observability-alerts in Mosher-Labs/homelab-gitops). Down means Grafana, Prometheus or the homelab cluster stopped."
  grace   = 600
  methods = "POST"
  name    = "homelab alerting heartbeat"
  tags    = ["grafana", "homelab"]
  timeout = 300
}
