# Creates a dedicated Google Cloud service account for GKE worker nodes.
resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = var.node_service_account_id
  display_name = "GKE node service account for ${var.cluster_name}"
}

# Grants the node identity the minimum project role required by GKE system components.
resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}