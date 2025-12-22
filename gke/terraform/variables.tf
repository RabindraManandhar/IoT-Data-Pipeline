# Variables for IoT Data Pipeline GKE Deployment

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "prj-mtp-aiot-dip"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "europe-north1"
}

variable "zone" {
  description = "GCP zone for resources"
  type        = string
  default     = "europe-north1-a"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "iot-pipeline-cluster"
}

variable "network_name" {
  description = "VPC network name"
  type        = string
  default     = "iot-pipeline-network"
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
  default     = "iot-pipeline-subnet"
}

variable "subnet_cidr" {
  description = "Subnet CIDR range"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pods_cidr" {
  description = "CIDR range for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "CIDR range for services"
  type        = string
  default     = "10.2.0.0/16"
}

variable "master_ipv4_cidr" {
  description = "CIDR range for GKE master"
  type        = string
  default     = "10.3.0.0/28"
}

# Node pool configuration
variable "node_machine_type" {
  description = "Machine type for cluster nodes"
  type        = string
  default     = "e2-standard-4" # 4 vCPUs, 16GB RAM
}

variable "min_node_count" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}

variable "disk_size_gb" {
  description = "Disk size in GB"
  type        = number
  default     = 100
}

variable "enable_private_cluster" {
  description = "Enable private GKE cluster"
  type        = bool
  default     = false # Set to true for production
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity"
  type        = bool
  default     = true
}

variable "artifact_registry_repository" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "iot-pipeline"
}

# Database configuration
variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "kafka_cluster_id" {
  description = "Kafka cluster ID"
  type        = string
  sensitive   = true
}

variable "grafana_password" {
  description = "Grafana password"
  type        = string
  sensitive   = true
}