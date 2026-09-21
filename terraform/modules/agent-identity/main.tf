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

# Three permissions, one per call the worker makes: Create with an
# ifGenerationMatch=0 precondition, Read, and List under a prefix.
#
# Overwrite needs storage.objects.delete as well as storage.objects.create,
# so leaving delete out removes both ways of losing a record. The ledger is
# append-only in IAM as well as in the client, and the two say it
# independently.
#
# The predefined pair that comes closest, objectCreator plus objectViewer,
# carries folder, managed folder and multipart upload permissions this
# worker never calls, so the role is written out instead.
resource "google_project_iam_custom_role" "ledger_appender" {
  project     = var.project_id
  role_id     = var.ledger_role_id
  title       = "Ledger appender"
  description = "Create, read and list ledger objects. No delete, so no overwrite either."

  permissions = [
    "storage.objects.create",
    "storage.objects.get",
    "storage.objects.list",
  ]
}

# Replaces roles/storage.objectUser, which covered delete and overwrite on
# the records the ledger exists to keep.
resource "google_storage_bucket_iam_member" "ledger_writer" {
  bucket = var.ledger_bucket_name
  role   = google_project_iam_custom_role.ledger_appender.id
  member = "serviceAccount:${google_service_account.triage.email}"
}

# One permission, for the one call the worker makes: generateContent on a
# publisher model. roles/aiplatform.user, which this replaces, also allows
# creating training jobs, pipelines, endpoints and notebooks, which is
# credit-balance abuse held by the one identity that parses
# attacker-influenced strings.
resource "google_project_iam_custom_role" "model_invoker" {
  project     = var.project_id
  role_id     = var.model_role_id
  title       = "Model invoker"
  description = "Call a Vertex AI publisher model. Nothing else."

  permissions = [
    "aiplatform.endpoints.predict",
  ]
}

# A new custom role can be invisible to IAM for a short while after it is
# created, and this binding then fails with "does not exist in the
# resource's hierarchy". Applying again binds it. See troubleshooting.md.
resource "google_project_iam_member" "vertex_user" {
  project = var.project_id
  role    = google_project_iam_custom_role.model_invoker.id
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
