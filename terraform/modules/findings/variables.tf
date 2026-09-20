variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "topic_name" {
  description = "Topic the Security Command Center notification config publishes to"
  type        = string
  default     = "scc-findings"
}

variable "subscription_name" {
  description = "Subscription the triage worker pulls from"
  type        = string
  default     = "scc-triage"
}

variable "ledger_bucket_name" {
  description = "Bucket holding one object per triage verdict. Globally unique, so it carries the project id."
  type        = string
}

variable "message_retention" {
  description = "How long an unacknowledged message survives. The exit criterion stops the worker mid-delivery, so this is the window the proof has to fit inside."
  type        = string
  default     = "604800s"

  validation {
    condition     = can(regex("^[0-9]+s$", var.message_retention))
    error_message = "The message_retention must be a duration in seconds, such as 604800s"
  }
}

variable "ack_deadline_seconds" {
  description = "How long the worker has to acknowledge before Pub/Sub redelivers. One model call plus a ledger write, with headroom."
  type        = number
  default     = 120

  validation {
    condition     = var.ack_deadline_seconds >= 10 && var.ack_deadline_seconds <= 600
    error_message = "The ack_deadline_seconds must be between 10 and 600"
  }
}

variable "max_delivery_attempts" {
  description = "Deliveries before a message goes to the dead letter topic"
  type        = number
  default     = 5

  validation {
    condition     = var.max_delivery_attempts >= 5 && var.max_delivery_attempts <= 100
    error_message = "The max_delivery_attempts must be between 5 and 100"
  }
}

variable "region" {
  description = "Region the ledger bucket is created in"
  type        = string
  default     = "europe-north1"
}

variable "project_number" {
  description = "The project's numeric id, used to name the Pub/Sub service agent. Passed in rather than read from a data source, because a deferred read makes it unknown at plan time and member is ForceNew on an IAM member."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{6,20}$", var.project_number))
    error_message = "The project_number must be the numeric project id"
  }
}
