terraform {
  required_version = "1.16.5"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "4.25.0"
    }
  }

  # Same pattern as observability-alerts: state is a Secret in this cluster's
  # terraform-state namespace. See RUNBOOK.md.
  backend "kubernetes" {
    # checkov:skip=CKV_SECRET_6: The suffix of the state Secret's name, not a secret value
    secret_suffix = "datadog-alerts"
    namespace     = "terraform-state"
    config_path   = "~/k3s.yaml"
  }
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
}
