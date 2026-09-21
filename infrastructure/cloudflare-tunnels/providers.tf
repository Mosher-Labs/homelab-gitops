terraform {
  required_version = "~> 1.3"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # State lives in this same k3s cluster (not Terraform Cloud, not
  # GitHub) as a Secret — no new account, no cost, and it stays in the
  # same trust boundary as everything this stack provisions for.
  #
  # The `terraform-state` namespace is NOT managed by this stack (or by
  # ArgoCD) — see RUNBOOK.md for the one-time `kubectl create namespace`
  # step. Keep it out of every ArgoCD Application's tracked resources;
  # a prune could otherwise delete this state Secret.
  backend "kubernetes" {
    secret_suffix = "cloudflare-tunnels"
    namespace     = "terraform-state"
    config_path   = "~/k3s.yaml"
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
