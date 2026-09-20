# The worker's own identity. It reads findings and writes verdicts, and
# holds nothing on the cluster: Phase 16 owns cluster reads.
resource "google_service_account" "triage" {
  project      = var.project_id
  account_id   = var.account_id
  display_name = "Security Command Center triage worker"
  description  = "Pulls findings, calls Vertex AI, writes verdicts. No cluster access."
}

# Scoped to the one subscription rather than granted on the project.
resource "google_pubsub_subscription_iam_member" "subscriber" {
  project      = var.project_id
  subscription = var.subscription_name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.triage.email}"
}

# objectUser covers read, create and delete on objects. It also carries
# storage.buckets.get and storage.buckets.list, so it is not scoped to
# objects alone. The ledger is written twice per verdict.
resource "google_storage_bucket_iam_member" "ledger_writer" {
  bucket = var.ledger_bucket_name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.triage.email}"
}

# roles/aiplatform.user is broader than what this worker calls: a
# publisher model needs only aiplatform.endpoints.predict, and a custom
# role holding that one permission would be narrower than this, which
# also allows creating training jobs, pipelines, endpoints and notebooks.
# Deferred rather than fixed, because a custom role needs a definition
# and an apply to verify against, and this branch is not applied yet.
resource "google_project_iam_member" "vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.triage.email}"
}

# Verdicts reach the email channel as log entries, so writing them is the
# notification path rather than incidental telemetry.
resource "google_project_iam_member" "log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.triage.email}"
}

# Workload Identity. No key is created, which is what the annotation on
# the Kubernetes service account completes.
resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.triage.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/${var.kubernetes_service_account}]"
}
