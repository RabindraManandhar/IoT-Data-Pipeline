
# Create SSD storage class for high-performance workloads (Kafka, TimescaleDB PVCs)
resource "kubernetes_storage_class" "ssd" {
  metadata {
    name = "fast-ssd"
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type             = "pd-ssd"
    replication-type = "regional-pd"
  }

  depends_on = [google_container_cluster.primary]
}

# Standard persistent disk storage class (Prometheus, Grafana, AlertManager, Mosquitto PVCs.)
resource "kubernetes_storage_class" "regional" {
  metadata {
    name = "standard-storage"
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type             = "pd-standard"
    replication-type = "regional-pd"
  }

  depends_on = [google_container_cluster.primary]
}