# SQL over logs already ingested. Import _Default once before the first apply.
resource "google_logging_project_bucket_config" "default" {
  # Match the API's stored "projects/ID" form, or the plan replaces the bucket.
  project        = "projects/${var.project_id}"
  location       = "global"
  bucket_id      = "_Default"
  retention_days = 30

  enable_analytics = true
}

# Counts nginx failures the uptime check cannot see. Not severity>=ERROR.
resource "google_logging_metric" "nginx_errors" {
  project     = var.project_id
  name        = "nginx-error-level"
  description = "nginx lines at error level or worse, taken from the container's own log level rather than the severity GKE assigns to stderr."

  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.namespace_name="${var.namespace}"
    resource.labels.container_name="nginx"
    textPayload=~"\[(error|crit|alert|emerg)\]"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}
