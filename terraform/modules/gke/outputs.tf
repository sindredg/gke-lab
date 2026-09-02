output "cluster_id" {
  description = "Identifier of the GKE cluster."
  value       = google_container_cluster.main.id
}

output "cluster_name" {
  description = "Name of the GKE cluster."
  value       = google_container_cluster.main.name
}

output "cluster_location" {
  description = "Zone containing the GKE cluster."
  value       = google_container_cluster.main.location
}

output "node_service_account_email" {
  description = "Email address of the GKE node service account."
  value       = google_service_account.nodes.email
}

output "node_pool_name" {
  description = "Name of the general-purpose GKE node pool."
  value       = google_container_node_pool.general.name
}