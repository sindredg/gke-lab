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