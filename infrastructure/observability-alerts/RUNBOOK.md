# RUNBOOK.md - observability-alerts

## Overview

Terraform stack that creates the homelab's Kubernetes alerts in Grafana, using
[Mosher-Labs/terraform-kubernetes-observability](https://github.com/Mosher-Labs/terraform-kubernetes-observability).
It creates a folder, "Kubernetes alerts (homelab)", with the module's alert
catalog for a k3s cluster, plus a Slack contact point and the notification
policy once the Slack token is set.

These are Grafana-managed alerts. They live in Grafana (Alerting → Alert rules)
and are routed by Grafana's own Alertmanager, not by the kube-prometheus-stack
Alertmanager or the PrometheusRules in `infrastructure/kube-prometheus-stack`.

## State

State is a Secret in the `terraform-state` namespace, the same as
`cloudflare-tunnels`. That namespace already exists.

## Credentials

- **Grafana:** the admin user from the `monitoring/grafana-admin` Secret, which
  comes from the 1Password item "Grafana".
- **Slack:** the Heimdallr bot token, in the 1Password item "Slack Heimdallr
  OAuth Token" (vault "Mosher Home", field `credential`), posting to channel
  `C0862CB6P8W`. The bot needs `chat:write`, plus `chat:write.customize` to post
  as "Heimdallr" rather than Grafana's default "Grafana". Leave `TF_VAR_slack`
  unset to keep notifications off.
- **Webex:** an incoming webhook into the alerts space, in the 1Password item
  "Webex Heimdallr Webhook Token" (field `credential`). Leave
  `TF_VAR_webex_webhook_url` unset to keep Webex off. Webhook posts show the
  webhook's initial as the avatar; a Webex bot would show Heimdallr's logo.

## Running Terraform

```bash
export KUBECONFIG=~/k3s.yaml
export TF_VAR_grafana_auth="$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-user}' | base64 -d):$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
# Turns on Slack. Without it, the plan removes the contact point.
export TF_VAR_slack="{token=\"$(op read 'op://Mosher Home/Slack Heimdallr OAuth Token/credential')\", recipient=\"C0862CB6P8W\"}"
# Turns on Webex. Without it, the plan removes Webex from the contact point.
export TF_VAR_webex_webhook_url="$(op read 'op://Mosher Home/Webex Heimdallr Webhook Token/credential')"
terraform init
terraform plan
terraform apply
```

## Tuning

Override a rule's threshold, pending period or severity in `main.tf` with
`alerts.overrides`, or turn it off with `alerts.disabled_rules`. Rule IDs are
listed in the module's README.
