output "network_id" {
  description = "Identifier of the custom VPC network."
  value       = google_compute_network.main.id
}

output "network_name" {
  description = "Name of the custom VPC network."
  value       = google_compute_network.main.name
}

output "subnet_id" {
  description = "Identifier of the GKE subnet."
  value       = google_compute_subnetwork.main.id
}

output "subnet_name" {
  description = "Name of the GKE subnet."
  value       = google_compute_subnetwork.main.name
}

output "pod_secondary_range_name" {
  description = "Name of the subnet secondary range allocated to Pods."
  value       = local.pod_secondary_range_name
}

output "router_name" {
  description = "Name of the Cloud Router used by Cloud NAT."
  value       = google_compute_router.main.name
}

output "nat_name" {
  description = "Name of the Cloud NAT configuration."
  value       = google_compute_router_nat.main.name
}
