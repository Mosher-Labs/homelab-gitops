# RUNBOOK.md - datadog-alerts

## Overview

Terraform stack that creates the homelab's Kubernetes alerts in Datadog, using
`modules/datadog` from
[Mosher-Labs/terraform-kubernetes-observability](https://github.com/Mosher-Labs/terraform-kubernetes-observability).
It creates the module's monitors for a k3s cluster, plus the Slack channel
`#datadog-alerts` and a Webex webhook that the monitors notify.

This runs next to the Grafana alerts (`infrastructure/observability-alerts`),
so we can compare how Datadog alerts and what its messages look like. Datadog
runs on its free trial: see `infrastructure/datadog/README.md`.

The Agent that sends the metrics is `infrastructure/datadog`. It tags every
metric `kube_cluster_name:homelab`, which these monitors match.

## State

State is a Secret in the `terraform-state` namespace, the same as
`observability-alerts`.

## Credentials

- **Datadog:** the 1Password items "datadog api key" and "datadog app key"
  (field `credential`). Create them in Datadog under Organization Settings.
- **Webex:** the Heimdallr bot token, in the 1Password item "webex heimdallr bot
  token".

## Slack

The Datadog Slack app must be installed in the workspace first, from Datadog's
Integrations → Slack tile (done; the account is `Mosher_Labs`). Terraform adds
the channel. If the channel was added in the tile first, `apply` fails with
"Channel is already configured". Import it:

```bash
terraform import 'module.datadog_alerts.datadog_integration_slack_channel.this[0]' 'Mosher_Labs:#datadog-alerts'
```

## Running Terraform

```bash
export KUBECONFIG=~/k3s.yaml
export TF_VAR_datadog_api_key="$(op item get 'datadog api key' --vault 'Mosher Home' --fields credential --reveal)"
export TF_VAR_datadog_app_key="$(op item get 'datadog app key' --vault 'Mosher Home' --fields credential --reveal)"
export TF_VAR_webex_bot_token="$(op read 'op://Mosher Home/webex heimdallr bot token/credential')"
terraform init
terraform plan
terraform apply
```

## Tuning

Override a rule's threshold, evaluation window or severity in `main.tf` with
`overrides`, or turn one off with `disabled_rules`. The module's README has the
rule IDs and which rules map to Datadog.

## Removing Datadog

Run `terraform destroy` here (it removes the monitors, the Slack channel and
the webhook), then delete this directory and `infrastructure/datadog`.
