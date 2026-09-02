variable "project_id" {
  description = "Google Cloud project ID in which the network will be created."
  type        = string
}

variable "region" {
  description = "Google Cloud region in which the subnet will be created."
  type        = string
}

variable "network_name" {
  description = "Name of the custom VPC network."
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet used by the GKE cluster."
  type        = string
}

variable "node_ipv4_cidr" {
  description = "Primary IPv4 CIDR range used by GKE nodes."
  type        = string

  validation {
    condition     = can(cidrhost(var.node_ipv4_cidr, 0))
    error_message = "node_ipv4_cidr must use valid CIDR notation."
  }
}

variable "pod_ipv4_cidr" {
  description = "Secondary IPv4 CIDR range used by Kubernetes Pods."
  type        = string

  validation {
    condition     = can(cidrhost(var.pod_ipv4_cidr, 0))
    error_message = "pod_ipv4_cidr must use valid CIDR notation."
  }
}
