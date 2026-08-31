# Stores the container images this project builds, in the same region as the cluster.
resource "google_artifact_registry_repository" "main" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "Container images built by the ${var.repository_id} project"
  format        = "DOCKER"

  docker_config {
    # Refuses to move a tag that already exists, so a tag names the same bytes for life.
    immutable_tags = true
  }

  # Untagged images accumulate on every rebuild and are unreachable once superseded.
  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"

    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s"
    }
  }

  # Protects the most recent images from the rule above regardless of their state.
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"

    most_recent_versions {
      keep_count = 10
    }
  }

  labels = var.resource_labels
}

# Lets the nodes pull from this repository only, rather than from every repository in the project.
resource "google_artifact_registry_repository_iam_member" "node_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.main.location
  repository = google_artifact_registry_repository.main.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.node_service_account_email}"
}