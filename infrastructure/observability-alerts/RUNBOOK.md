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
- **Slack:** a bot token (`xoxb-...`) with `chat:write`, and the ID of the
  channel to post in. The bot must be a member of that channel. Leave
  `TF_VAR_slack` unset to keep notifications off.

## Running Terraform

```bash
export KUBECONFIG=~/k3s.yaml
export TF_VAR_grafana_auth="$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-user}' | base64 -d):$(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
# Optional, turns on Slack:
# export TF_VAR_slack="{token=\"$(op read 'op://Mosher Home/<item>/token')\", recipient=\"<channel ID>\"}"
terraform init
terraform plan
terraform apply
```

## Tuning

Override a rule's threshold, pending period or severity in `main.tf` with
`alerts.overrides`, or turn it off with `alerts.disabled_rules`. Rule IDs are
listed in the module's README.
