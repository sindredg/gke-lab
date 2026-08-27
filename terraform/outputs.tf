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