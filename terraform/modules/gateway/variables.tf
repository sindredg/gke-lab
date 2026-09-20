variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "address_name" {
  description = "Name of the reserved external address the Gateway attaches to"
  type        = string
  default     = "k8-lab-gateway"
}

variable "domain" {
  description = "The root or subdomain to issue the SSL certificate for"
  type        = string
}

variable "project_number" {
  description = "The project's numeric id. Passed in rather than read from a data source, because a deferred read makes it unknown at plan time and the certificate's dns_authorizations is ForceNew."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{6,20}$", var.project_number))
    error_message = "The project_number must be the numeric project id"
  }
}
