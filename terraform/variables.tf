variable "project_id" {
  description = "The GCP project ID"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id must be a valid GCP project ID"
  }
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "europe-north1"
}

variable "zone" {
  description = "The GCP zone"
  type        = string
  default     = "europe-north1-a"
}

variable "node_zones" {
  description = "Zones the node pool may place nodes in. Includes the cluster's own zone."
  type        = list(string)
  default     = ["europe-north1-a", "europe-north1-b", "europe-north1-c"]

  validation {
    condition     = contains(var.node_zones, var.zone)
    error_message = "The node_zones must include the cluster's zone."
  }
}

variable "domain" {
  description = "The domain name for the Gateway and SSL certificate"
  type        = string
}

variable "alert_email" {
  description = "Address the availability alert notifies. Kept out of the repository with every other value in tfvars."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.alert_email))
    error_message = "The alert_email must be a valid email address"
  }
}

variable "project_number" {
  description = "The project's numeric id, which some APIs store instead of the project id. Kept in tfvars with every other value."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{6,20}$", var.project_number))
    error_message = "The project_number must be the numeric project id"
  }
}
