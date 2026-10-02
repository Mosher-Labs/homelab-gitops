output "alert_folder_uid" {
  description = "UID of the Grafana folder that holds the alert rules."
  value       = module.observability.alert_folder_uid
}

output "alert_rule_ids" {
  description = "The alert rules that were created."
  value       = module.observability.alert_rule_ids
}

output "enabled_channels" {
  description = "The notification channels that are turned on."
  value       = module.observability.enabled_channels
}
