# Service Account for GKE nodes
resource "google_service_account" "gke_nodes" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "Service Account for GKE nodes"
  project      = var.project_id
}

# IAM roles for node service account
resource "google_project_iam_member" "gke_nodes_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# GKE Cluster Configuration
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.zone
  project  = var.project_id

  # Do not protect the cluster from deletion (you want to destroy via Terraform)
  deletion_protection = false

  # Remove default node pool because we want full control using our own separate node pool resources
  remove_default_node_pool = true
  initial_node_count       = 1

  # Network configuration (VPC + Subnet)

  # Attach cluster to custom VPC
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # Enable IP aliasing and map pod + service CIDRs
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private cluster configuration (optional)
  dynamic "private_cluster_config" {
    for_each = var.enable_private_cluster ? [1] : []
    content {
      # Nodes have ONLY private IPs (more secure)
      enable_private_nodes    = true

      # API server still publicly accessible (recommeded for dev)
      enable_private_endpoint = false

      # CIDR block from which master assigns private IP
      master_ipv4_cidr_block  = var.master_ipv4_cidr
    }
  }

  # Workload Identity
  # Allows Kubernetes service accounts to impersonate GCP service accounts
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Add-ons (Ingress, HPA, Network Policy)
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }

  # Network policy
  network_policy {
    enabled  = true
    provider = "PROVIDER_UNSPECIFIED"
  }

  # Maintenance window
  # Schedule cluster upgrades during low traffic window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00" # 3 AM Helsinki time
    }
  }

  # Monitoring and logging

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  # Release channel
  # REGULAR recommended for stability + good patching cadence
  release_channel {
    channel = "REGULAR"
  }

  # Cluster autoscaling (NOT NODE POOLS)
  # This controls resource-based autoscaling at cluster-level
  cluster_autoscaling {
    enabled = true
    resource_limits {
      resource_type = "cpu"
      minimum       = 4
      maximum       = 32
    }
    
    # Memory autoscaling boundaries
    resource_limits {
      resource_type = "memory"
      minimum       = 16
      maximum       = 128
    }
  }

  # Binary authorization (optional, for production)
  # binary_authorization {
  #   evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  # }

  depends_on = [
    google_compute_subnetwork.subnet,
    google_project_iam_member.gke_nodes_roles
  ]
}