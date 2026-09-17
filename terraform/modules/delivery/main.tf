# GitHub Actions as an external identity provider: tokens, not stored keys.
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "Federates GitHub Actions workflows into this project"
}

# Trusts GitHub's OIDC issuer, and only for the one repository named below.
resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  # Claims carried from the token. Only mapped attributes can be referenced.
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Repository alone lets any branch of it mint credentials; ref closes that.
  attribute_condition = join(" && ", compact([
    "assertion.repository == '${var.github_repository}'",
    var.github_ref == null ? "" : "assertion.ref == '${var.github_ref}'",
  ]))

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# The identity the workflow acts as. The pool only decides who may become it.
resource "google_service_account" "deploy" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "Delivery pipeline identity for ${var.github_repository}"
}

# principalSet names a group of identities rather than a single one.
resource "google_service_account_iam_member" "github_impersonation" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# Push rights on this one repository, not on every repository in the project.
resource "google_artifact_registry_repository_iam_member" "deploy_writer" {
  project    = var.project_id
  location   = var.region
  repository = var.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deploy.email}"
}

# Reaching the cluster only. What it may do inside is Kubernetes RBAC.
resource "google_project_iam_member" "deploy_cluster_viewer" {
  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}
