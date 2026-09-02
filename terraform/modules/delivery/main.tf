# Establishes GitHub Actions as an external identity provider for this project, workflows authenticate by signed token instead of stored key.
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

  # Claims carried across from the token. Only mapped attributes can be referenced by the condition below or by an IAM member string.
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Without this, the provider accepts a valid token from any repository on GitHub, including one an attacker creates.
  attribute_condition = "assertion.repository == '${var.github_repository}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# The identity the workflow acts as. It holds the permissions; the pool only decides who is allowed to become it.
resource "google_service_account" "deploy" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "Delivery pipeline identity for ${var.github_repository}"
}

# Lets any token carrying this repository attribute impersonate the account. principalSet names a group of identities instead of a single one.
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

# Permission to reach the cluster and read its endpoint, and nothing more.
# What the pipeline may do inside the cluster is Kubernetes RBAC, in Slice 2.
resource "google_project_iam_member" "deploy_cluster_viewer" {
  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = "serviceAccount:${google_service_account.deploy.email}"
}
