module "observability" {
  source = "git::https://github.com/Mosher-Labs/terraform-kubernetes-observability.git?ref=3c6bb53a14e7bf27fdaaa44d77766437d454c52b" # v0.17.0

  alerts = {
    # Service-level alerts and the dashboard's Services row, from apps that
    # serve OpenTelemetry-style request metrics. Today that's LiftTrace.
    apm = { enabled = true }
    # Homelab-specific rules; see locals.tf.
    custom_rules = merge(local.custom_rules, module.slo.custom_rules)
  }
  cluster_name = "homelab"
  cluster_type = "k3s"
  dashboards = {
    # Adds an error-logs panel from infrastructure/loki.
    loki_datasource_uid = "loki"
    # An SLO row for each SLO in locals.tf.
    slos = module.slo.dashboard_slos
  }
  # Each channel is on when its TF_VAR_ is set; see RUNBOOK.md.
  notifications = {
    enabled = nonsensitive(var.slack != null || var.webex_bot_token != null || var.webex_webhook_url != null)
    # Heimdallr's logo on Slack. The Webex bot has the same logo as its avatar.
    icon_url = "https://avatars.githubusercontent.com/u/195353313?v=4"
  }
  # Pings healthchecks.io while Grafana and Prometheus work; it emails if the
  # pings stop. See RUNBOOK.md.
  heartbeat = {
    url = healthchecksio_check.heartbeat.ping_url
  }
  prometheus_datasource_uid = "prometheus"
  slack = var.slack == null ? null : {
    recipient = var.slack.recipient
    token     = var.slack.token
    # Grafana posts as "Grafana" unless told otherwise.
    username = "Heimdallr"
  }
  # The Heimdallr bot when its token is set (it has the logo as its avatar),
  # otherwise the incoming webhook, otherwise no Webex.
  webex = var.webex_bot_token != null ? {
    room_id = local.webex_room_id
    token   = var.webex_bot_token
    } : var.webex_webhook_url != null ? {
    webhook_url = var.webex_webhook_url
  } : null
}

# Burn-rate alerts for the homelab's SLOs, defined in locals.tf and
# documented in docs/slos.
module "slo" {
  source = "git::https://github.com/Mosher-Labs/terraform-kubernetes-observability.git//modules/slo?ref=3c6bb53a14e7bf27fdaaa44d77766437d454c52b" # v0.17.0

  slos = local.slos
}
