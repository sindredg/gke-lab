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

output "gateway_address" {
  description = "Reserved public address of the external Gateway."
  value       = module.gateway.address
}

output "dns_authorization_record" {
  description = "CNAME record proving control of the domain."
  value       = module.gateway.dns_authorization_record
}

output "certificate_map_name" {
  description = "Certificate Manager map the Gateway annotation references."
  value       = module.gateway.certificate_map_name
}

output "uptime_check_id" {
  description = "Identifier of the public uptime check."
  value       = module.observability.uptime_check_id
}

output "alert_policy_name" {
  description = "Resource name of the availability alert policy."
  value       = module.observability.alert_policy_name
}

output "dashboard_id" {
  description = "Resource name of the workload health dashboard."
  value       = module.observability.dashboard_id
}

output "findings_topic_id" {
  description = "Topic Security Command Center publishes findings to."
  value       = module.findings.topic_id
}

output "triage_subscription_name" {
  description = "Subscription the triage worker pulls from."
  value       = module.findings.subscription_name
}

output "triage_dead_letter_subscription" {
  description = "Where to pull from when a verdict never appeared for a finding."
  value       = module.findings.dead_letter_subscription_name
}

output "verdict_ledger_bucket" {
  description = "Bucket holding one object per verdict."
  value       = module.findings.bucket_name
}

output "findings_notification_config" {
  description = "Resource name of the Security Command Center notification config."
  value       = module.findings.notification_config_name
}

output "triage_service_account_email" {
  description = "Identity the triage worker federates to. Matches the annotation on the agents ServiceAccount."
  value       = module.agent_identity.service_account_email
}
