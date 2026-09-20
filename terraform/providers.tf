provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  # Some APIs bill the caller's quota project rather than the resource's
  # project, and user Application Default Credentials carry no quota project.
  # Without this, securitycenter.googleapis.com bills Google's own shared
  # gcloud client project, 764086051850, where it is disabled, and the
  # notification config fails 403 SERVICE_DISABLED while the API is enabled
  # here. Set on the provider rather than by
  # gcloud auth application-default set-quota-project, so the fix lives with
  # the configuration instead of in one machine's credentials.
  billing_project       = var.project_id
  user_project_override = true
}
