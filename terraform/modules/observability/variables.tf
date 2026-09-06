variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "domain" {
  description = "The public hostname the uptime check requests"
  type        = string
}

variable "alert_email" {
  description = "Address the availability alert notifies. Must be confirmed at the inbox before the channel delivers."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.alert_email))
    error_message = "The alert_email must be a valid email address"
  }
}

variable "cluster_name" {
  description = "Cluster the dashboard's Kubernetes panels filter on"
  type        = string
}

variable "namespace" {
  description = "Namespace the dashboard's Kubernetes panels filter on"
  type        = string
  default     = "demo"
}

variable "uptime_check_regions" {
  description = "Checker regions. At least three are required once the set is named at all."
  type        = list(string)
  default     = ["EUROPE", "USA", "ASIA_PACIFIC"]

  validation {
    condition     = length(var.uptime_check_regions) >= 3
    error_message = "At least three checker regions are required"
  }
}
