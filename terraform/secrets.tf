# Create secrets in Google Secret Manager
resource "google_secret_manager_secret" "postgres_password" {
  secret_id = "postgres-password"
  project   = var.project_id

  replication {
    auto {

    }
  }
}

resource "google_secret_manager_secret_version" "postgres_password" {
  secret      = google_secret_manager_secret.postgres_password.id
  secret_data = var.postgres_password
}

resource "google_secret_manager_secret" "kafka_cluster_id" {
  secret_id = "kafka-cluster-id"
  project   = var.project_id

  replication {
    auto {

    }
  }
}

resource "google_secret_manager_secret_version" "kafka_cluster_id" {
  secret      = google_secret_manager_secret.kafka_cluster_id.id
  secret_data = var.kafka_cluster_id
}

# Service account for accessing secrets from GKE
resource "google_service_account" "secret_accessor" {
  account_id   = "gke-secret-accessor"
  display_name = "GKE Secret Accessor"
  project      = var.project_id
}

resource "google_secret_manager_secret_iam_member" "postgres_password_access" {
  secret_id = google_secret_manager_secret.postgres_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.secret_accessor.email}"
}

resource "google_secret_manager_secret_iam_member" "kafka_cluster_id_access" {
  secret_id = google_secret_manager_secret.kafka_cluster_id.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.secret_accessor.email}"
}

# Workload Identity binding
resource "google_service_account_iam_member" "workload_identity_binding" {
  service_account_id = google_service_account.secret_accessor.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[iot-pipeline/default]"
}