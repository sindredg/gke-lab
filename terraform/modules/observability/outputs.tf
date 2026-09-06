output "uptime_check_id" {
  description = "Identifier the alert policy filters on, and the one to name when reading check results"
  value       = google_monitoring_uptime_check_config.public.uptime_check_id
}

output "notification_channel_id" {
  description = "Channel the alert policy notifies. Confirm the address before trusting a drill."
  value       = google_monitoring_notification_channel.email.id
}

output "alert_policy_name" {
  description = "Full resource name of the availability alert policy"
  value       = google_monitoring_alert_policy.site_unavailable.name
}

output "dashboard_id" {
  description = "Full resource name of the workload health dashboard"
  value       = google_monitoring_dashboard.workload_health.id
}
