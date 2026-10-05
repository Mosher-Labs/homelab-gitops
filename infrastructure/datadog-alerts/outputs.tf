output "monitor_ids" {
  description = "Datadog monitor IDs, keyed by rule ID."
  value       = module.datadog_alerts.monitor_ids
}

output "skipped_rules" {
  description = "Catalog rules this backend doesn't create, with the reason."
  value       = module.datadog_alerts.skipped_rules
}
