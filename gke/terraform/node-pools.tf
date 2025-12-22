# Primary node pool for application workloads
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-primary-pool"
  location   = var.zone
  cluster    = google_container_cluster.primary.name
  project    = var.project_id

  # Start with a fixed count with autoscaling
  initial_node_count = var.min_node_count

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # # Ensure nodes don't get external IPs (satisfies org policy)
  # network_config {
  #   enable_private_nodes = false  # Set to true if you want fully private nodes
  # }

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

    # Shielded VM configuration
    shielded_instance_config {
      enable_secure_boot          = true # Required by org policy
      enable_integrity_monitoring = true
    }

    # # FIXED: Add advanced_machine_features to prevent external IP assignment
    # # This satisfies the compute.vmExternalIpAccess constraint
    # advanced_machine_features {
    #   enable_nested_virtualization = false
    #   threads_per_core            = 1
    # }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  # Add timeout for node pool creation
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  # Ensure cluster is fully ready before creating node pool
  depends_on = [
    google_container_cluster.primary
  ]
}

# Optional: Separate node pool for Kafka (if needed for resource isolation)
resource "google_container_node_pool" "kafka_nodes" {
  count      = 1 # Set to 1 to enable
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
    machine_type = var.node_machine_type
    disk_size_gb = var.disk_size_gb
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

    # Updated shielded_instance_config to satisfy org policy
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}