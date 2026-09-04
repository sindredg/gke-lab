output "address_name" {
  description = "Name the Gateway references, not the address itself"
  value       = google_compute_global_address.gateway.name
}

output "address" {
  description = "The reserved IPv4 address, for the DNS record"
  value       = google_compute_global_address.gateway.address
}

output "dns_authorization_record" {
  description = "The CNAME record proving domain control"
  value       = google_certificate_manager_dns_authorization.default.dns_resource_record
}

output "certificate_map_name" {
  description = "Name the Gateway annotation references"
  value       = google_certificate_manager_certificate_map.default.name
}