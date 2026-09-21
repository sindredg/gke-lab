variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "account_id" {
  description = "Short name of the Google service account the worker federates to"
  type        = string
  default     = "k8-lab-triage"
}

variable "namespace" {
  description = "Kubernetes namespace holding the service account this identity binds to"
  type        = string
  default     = "agents"
}

variable "kubernetes_service_account" {
  description = "Name of the Kubernetes service account bound to this identity"
  type        = string
  default     = "triage-worker"
}

variable "subscription_name" {
  description = "Subscription the worker may pull from. Scoped here rather than granting the role project-wide."
  type        = string
}

variable "ledger_bucket_name" {
  description = "Bucket the worker may read and write verdicts in"
  type        = string
}

variable "ledger_role_id" {
  description = "ID of the custom role holding the worker's three ledger permissions"
  type        = string
  default     = "k8_lab_ledger_appender"
}
