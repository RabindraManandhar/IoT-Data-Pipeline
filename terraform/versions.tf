# Main teffaform configuration for IoT Data Pipeline on GKE

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }

  # Optional: Configure remote backend for state management
  # backend "gcs" {
  #   bucket = "prj-mtp-aiot-dip-terraform-state"
  #   prefix = "terraform/state"
  # }
}

# Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# # Configure kubernetes provider with Oauth2 access token.
# # https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/client_config
# # This fetches a new token, which will expire in 1 hour.
# data "google_client_config" "default" {}# Data sources

# # Kubernetes Provider (configured after GKE cluster creation)
# provider "kubernetes" {
#   host                   = "https://${google_container_cluster.primary.endpoint}"
#   token                  = data.google_client_config.default.access_token
#   cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
# }

