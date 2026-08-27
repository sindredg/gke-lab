variable "project_id" {
  description = "The project ID to deploy the GKE cluster into."
  type        = string
}

variable "cluster_name" {
  description = "The name of the GKE cluster."
  type        = string
}

variable "zone" {
  description = "The zone to deploy the GKE cluster into."
  type        = string
}

variable "network_id" {
  description = "The ID of the VPC network to deploy the GKE cluster into."
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnetwork to deploy the GKE cluster into."
  type        = string
}

variable "pod_secondary_range_name" {
  description = "The name of the secondary range to use for pod IPs."
  type        = string
}

variable "node_service_account_id" {
  description = "The service account ID to use for the GKE nodes."
  type        = string
}

variable "node_pool_name" {
  description = "The name of the node pool to create."
  type        = string
}

variable "machine_type" {
  description = "The machine type to use for the GKE nodes."
  type        = string
  default     = "e2-standard-2"
}

variable "min_node_count" {
  description = "The minimum number of nodes in the node pool."
  type        = number
  default     = 1

  validation {
    condition     = var.min_node_count >= 1
    error_message = "The minimum node count must be at least 1."
  }
}

variable "max_node_count" {
  description = "The maximum number of nodes in the node pool."
  type        = number
  default     = 3

  validation {
    condition     = var.max_node_count >= var.min_node_count
    error_message = "The maximum node count must be greater than or equal to the minimum node count (1)."
  }
}

variable "disk_size_gb" {
  description = "The size of the disk to use for the GKE nodes, in GB."
  type        = number
  default     = 50
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection for the GKE cluster."
  type        = bool
  default     = true
}

variable "resource_labels" {
  description = "A map of resource labels to apply to the GKE cluster."
  type        = map(string)
  default     = {}
}