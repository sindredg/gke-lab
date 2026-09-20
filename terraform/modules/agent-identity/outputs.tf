output "service_account_email" {
  description = "Goes on the Kubernetes service account as iam.gke.io/gcp-service-account"
  value       = google_service_account.triage.email
}

output "service_account_name" {
  description = "Full resource name, for reading the Workload Identity binding back"
  value       = google_service_account.triage.name
}
