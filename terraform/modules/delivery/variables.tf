variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "Region holding the image repository"
  type        = string
}

variable "repository_id" {
  description = "Artifact Registry repository the pipeline may push to"
  type        = string
}

variable "github_repository" {
  description = "The only repository whose tokens this provider accepts, as owner/name"
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "Must be owner/name, with no host and no trailing slash."
  }
}

variable "pool_id" {
  description = "Identifier of the Workload Identity Pool"
  type        = string
  default     = "github"
}

variable "service_account_id" {
  description = "Account ID of the delivery pipeline identity"
  type        = string
  default     = "k8-lab-deploy"
}
