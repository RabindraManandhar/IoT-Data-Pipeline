# Primary node pool for application workloads
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-primary-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  project    = var.project_id
  node_count = var.min_node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    preemptible  = false
    machine_type = var.node_machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard"

    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = "development"
      workload    = "iot-pipeline"
    }

    tags = ["gke-node", "${var.cluster_name}-node"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# Optional: Separate node pool for Kafka (if needed for resource isolation)
resource "google_container_node_pool" "kafka_nodes" {
  count      = 0 # Set to 1 to enable
  name       = "${var.cluster_name}-kafka-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  project    = var.project_id
  node_count = 3

  autoscaling {
    min_node_count = 3
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    preemptible  = false
    machine_type = "e2-standard-4"
    disk_size_gb = 100
    disk_type    = "pd-ssd" # SSD for better Kafka performance

    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = "production"
      workload    = "kafka"
    }

    tags = ["gke-node", "${var.cluster_name}-kafka-node"]

    taint {
      key    = "workload"
      value  = "kafka"
      effect = "NO_SCHEDULE"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}