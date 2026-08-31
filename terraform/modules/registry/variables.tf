variable "project_id" {
  description = "The project ID to create the Artifact Registry repository in."
  type        = string
}

variable "region" {
  description = "The region to create the Artifact Registry repository in. Match the cluster region to avoid cross-region pull latency and egress cost."
  type        = string
}

variable "repository_id" {
  description = "The name of the Artifact Registry repository."
  type        = string
}

variable "node_service_account_email" {
  description = "Email address of the GKE node service account that pulls images. Image pulls use the node identity, not the Pod identity."
  type        = string
}

variable "resource_labels" {
  description = "Labels applied to the repository."
  type        = map(string)
  default     = {}
}
