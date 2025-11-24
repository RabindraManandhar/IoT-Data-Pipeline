# Artifact Registry repository for Docker images
resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = var.artifact_registry_repository
  description   = "Docker repository for IoT Pipeline images"
  format        = "DOCKER"
  project       = var.project_id

  # Set cleanup policy to false to prevent deletion issues
  cleanup_policy_dry_run = false

  # FIXED: Prevent accidental deletion (comment out if you need to destroy)
  # lifecycle {
  #   prevent_destroy = false
  # }
}

# IAM binding for GKE to pull images
resource "google_artifact_registry_repository_iam_member" "gke_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.docker_repo.location
  repository = google_artifact_registry_repository.docker_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.gke_nodes.email}"

  depends_on = [google_artifact_registry_repository.docker_repo]
}