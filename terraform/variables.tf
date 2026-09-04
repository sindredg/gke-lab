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

variable "domain" {
  description = "The domain name for the Gateway and SSL certificate"
  type        = string
}