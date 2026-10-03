terraform {
  required_version = "1.16.5"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "4.47.0"
    }
    healthchecksio = {
      source  = "kristofferahl/healthchecksio"
      version = "2.3.0"
    }
  }

  # Same pattern as cloudflare-tunnels: state is a Secret in this cluster's
  # terraform-state namespace. See RUNBOOK.md.
  backend "kubernetes" {
    # checkov:skip=CKV_SECRET_6: The suffix of the state Secret's name, not a secret value
    secret_suffix = "observability-alerts"
    namespace     = "terraform-state"
    config_path   = "~/k3s.yaml"
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_auth
}

provider "healthchecksio" {
  api_key = var.healthchecksio_api_key
}
