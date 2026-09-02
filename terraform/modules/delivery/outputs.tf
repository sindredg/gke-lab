output "workload_identity_provider" {
  description = "Full provider resource name the GitHub auth step needs"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "deploy_service_account_email" {
  description = "Email of the delivery pipeline identity"
  value       = google_service_account.deploy.email
}