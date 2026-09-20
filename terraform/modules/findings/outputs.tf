output "topic_id" {
  description = "Full resource id of the topic findings arrive on"
  value       = google_pubsub_topic.findings.id
}

output "subscription_name" {
  description = "Short name of the subscription the worker pulls from"
  value       = google_pubsub_subscription.triage.name
}

output "dead_letter_topic_id" {
  description = "Where a message goes after five failed deliveries. The topic itself has no subscription and is not readable; pull from dead_letter_subscription_name instead."
  value       = google_pubsub_topic.dead_letter.id
}

output "dead_letter_subscription_name" {
  description = "Where to pull from when a verdict never appeared for a finding."
  value       = google_pubsub_subscription.dead_letter.name
}

output "bucket_name" {
  description = "Verdict ledger. One object per finding, event time and state."
  value       = google_storage_bucket.ledger.name
}

output "notification_config_name" {
  description = "Full resource name of the notification config, for reading its state back"
  value       = google_scc_v2_project_notification_config.findings.name
}

output "notification_service_account" {
  description = "Agent the config publishes as. Named by Google after the config exists, which is why the publisher binding depends on the config."
  value       = google_scc_v2_project_notification_config.findings.service_account
}
