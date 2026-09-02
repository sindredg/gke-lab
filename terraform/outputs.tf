output "network_id" {
  description = "Identifier of the GKE VPC network."
  value       = module.network.network_id
}

output "subnet_id" {
  description = "Identifier of the GKE subnet."
  value       = module.network.subnet_id
}

output "pod_secondary_range_name" {
  description = "Name of the Pod secondary address range."
  value       = module.network.pod_secondary_range_name
}

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = module.gke.cluster_name
}

output "cluster_location" {
  description = "Zone containing the GKE cluster."
  value       = module.gke.cluster_location
}

output "node_service_account_email" {
  description = "Email address of the GKE node service account."
  value       = module.gke.node_service_account_email
}

output "registry_url" {
  description = "URL of the private image repository."
  value       = module.registry.registry_url
}

output "workload_identity_provider" {
  description = "Full provider resource name for the GitHub Actions auth step."
  value       = module.delivery.workload_identity_provider
}

output "deploy_service_account_email" {
  description = "Email of the delivery pipeline identity."
  value       = module.delivery.deploy_service_account_email
}