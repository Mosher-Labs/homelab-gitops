locals {
  # Rules for this cluster that the module's catalog doesn't cover. They used to
  # be PrometheusRules in infrastructure/kube-prometheus-stack/manifests.
  custom_rules = {
    argocd_app_out_of_sync = {
      expr           = "max by (name, sync_status) (argocd_app_info{sync_status!=\"Synced\"})"
      group          = "argocd"
      operator       = "gt"
      pending_period = "30m"
      severity       = "warning"
      subject        = "{{ $labels.name }}"
      summary        = "Argo CD app {{ $labels.name }} has been {{ $labels.sync_status }} for 30 minutes."
      threshold      = 0
      title          = "Argo CD app out of sync"
    }
    argocd_app_sync_unknown = {
      expr           = "max by (name) (argocd_app_info{sync_status=\"Unknown\"})"
      group          = "argocd"
      operator       = "gt"
      pending_period = "5m"
      severity       = "critical"
      subject        = "{{ $labels.name }}"
      summary        = "Argo CD can't tell whether app {{ $labels.name }} is in sync, which usually means a failed sync or a broken manifest."
      threshold      = 0
      title          = "Argo CD app sync unknown"
    }
    argocd_app_unhealthy = {
      expr           = "max by (name, health_status) (argocd_app_info{health_status!~\"Healthy|Progressing\"})"
      group          = "argocd"
      operator       = "gt"
      pending_period = "15m"
      severity       = "warning"
      subject        = "{{ $labels.name }}"
      summary        = "Argo CD app {{ $labels.name }} has been {{ $labels.health_status }} for 15 minutes."
      threshold      = 0
      title          = "Argo CD app unhealthy"
    }
    argocd_repo_server_unavailable = {
      expr           = "max(kube_deployment_status_replicas_available{deployment=\"argocd-repo-server\",namespace=\"argocd\"})"
      group          = "argocd"
      operator       = "lt"
      pending_period = "5m"
      severity       = "critical"
      subject        = "argocd-repo-server"
      summary        = "The Argo CD repo server has no available replicas, so apps can't sync."
      threshold      = 1
      title          = "Argo CD repo server down"
    }
    argocd_server_unavailable = {
      expr           = "max(kube_deployment_status_replicas_available{deployment=\"argocd-server\",namespace=\"argocd\"})"
      group          = "argocd"
      operator       = "lt"
      pending_period = "5m"
      severity       = "critical"
      subject        = "argocd-server"
      summary        = "The Argo CD server has no available replicas, so GitOps deployments stop."
      threshold      = 1
      title          = "Argo CD server down"
    }
    # These volumes mount with nofail, so a node boots and reports Ready without
    # them, and every threshold alert on the mount goes quiet instead of firing.
    # Missing k3s storage also sends new PVs back to the root disk.
    node_expected_mount_missing = {
      expr           = "absent(node_filesystem_size_bytes{mountpoint=\"/var/lib/rancher/k3s/storage\"}) or absent(node_filesystem_size_bytes{mountpoint=\"/data\"})"
      group          = "nodes"
      operator       = "gt"
      pending_period = "5m"
      severity       = "critical"
      subject        = "{{ $labels.mountpoint }}"
      summary        = "No filesystem metrics for {{ $labels.mountpoint }}: the mount is missing. Check findmnt and lvs on the node."
      threshold      = 0
      title          = "Expected mount missing"
    }
  }

  # The "homelab alerts" Webex space. An identifier, not a secret: posting
  # needs the bot token.
  webex_room_id = "Y2lzY29zcGFyazovL3VybjpURUFNOnVzLXdlc3QtMl9yL1JPT00vNTg1NzRlYTAtYmViOS0xMWYxLWExMjMtNzMwYWE2OGZkMjY3"
}

locals {
  # SLOs with burn-rate alerts. See docs/slos for each SLO document.
  slos = {
    pihole_dns = {
      title  = "Pi-hole DNS"
      target = 0.999
      # One DNS probe a minute from the blackbox exporter. The fast tier is left
      # out: a single failed probe in an hour would be a burn rate of 16.7 and
      # page for a blip.
      grafana = {
        error_ratio = "1 - avg_over_time(probe_success{target=\"pihole-dns\"}[$${window}])"
      }
      tiers = ["medium", "slow"]
    }
  }
}
