# These logs are already ingested and already billed. Analytics adds SQL over them
# at no extra storage cost, which is the cheapest capability available here.
#
# _Default exists before Terraform does, so this resource has to be imported once
# before the first apply. Without the import the apply fails with "already exists".
#
#   terraform -chdir=terraform import \
#     'module.observability.google_logging_project_bucket_config.default' \
#     'projects/PROJECT_ID/locations/global/buckets/_Default'
#
# Enabling analytics on a bucket cannot be undone.
resource "google_logging_project_bucket_config" "default" {
  # Import writes this back in the API's "projects/ID" form. Supplying the bare ID
  # here reads as a change to an immutable field and plans a replacement, which for a
  # log bucket means deleting it and every log in it. Matching the stored form keeps
  # the plan to the one attribute that is actually changing.
  project        = "projects/${var.project_id}"
  location       = "global"
  bucket_id      = "_Default"
  retention_days = 30

  enable_analytics = true
}

# Counts nginx failures that leave the site reachable, which the uptime check cannot see.
#
# Not severity>=ERROR. GKE labels every line a container writes to stderr as ERROR,
# and nginx writes its [notice] lines there, so a severity filter counts a graceful
# shutdown on every rollout. Measured before writing this: five ERROR entries over
# seven days, all [notice], all from one rollout.
#
# nginx states its own level in the message, so matching that is the filter that
# means what it says.
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
