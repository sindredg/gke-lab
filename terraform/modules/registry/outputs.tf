output "repository_id" {
  description = "Identifier of the Artifact Registry repository."
  value       = google_artifact_registry_repository.main.id
}

output "repository_name" {
  description = "Name of the Artifact Registry repository."
  value       = google_artifact_registry_repository.main.name
}

output "registry_url" {
  description = "Host and path that image references are built from."
  value       = "${google_artifact_registry_repository.main.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.name}"
}
