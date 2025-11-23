#!/bin/bash
# Script to import existing GCP resources into Terraform state
# This resolves 409 Conflict errors when resources already exist

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-prj-mtp-aiot-dip}"
REGION="${GCP_REGION:-europe-north1}"
ZONE="${GCP_ZONE:-europe-north1-a}"
CLUSTER_NAME="${GKE_CLUSTER_NAME:-iot-pipeline-cluster}"

echo -e "${GREEN}=========================================="
echo "Importing Existing GCP Resources to Terraform"
echo "==========================================${NC}"

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform is not installed${NC}"
    echo -e "${YELLOW}Please install Terraform first:${NC}"
    echo "  https://developer.hashicorp.com/terraform/downloads"
    exit 1
fi
echo -e "${GREEN}✅ Terraform is installed: $(terraform version -json | grep -o '"version":"[^"]*' | cut -d'"' -f4)${NC}"

if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}❌ gcloud CLI is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ gcloud CLI is installed${NC}"

# Check gcloud authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
    echo -e "${RED}❌ Not authenticated with gcloud${NC}"
    echo "Please run: gcloud auth login"
    exit 1
fi
echo -e "${GREEN}✅ Authenticated with gcloud${NC}"

# Set project
gcloud config set project ${PROJECT_ID} --quiet
echo -e "${GREEN}✅ Project set to ${PROJECT_ID}${NC}"

# Function to safely import a resource
safe_import() {
    local resource_address=$1
    local resource_id=$2
    local resource_name=$3
    
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Checking ${resource_name}...${NC}"
    
    # Check if resource is already in state
    if terraform state show "$resource_address" &>/dev/null; then
        echo -e "${GREEN}✓ ${resource_name} already in state${NC}"
        return 0
    fi
    
    # Try to import with detailed error output
    echo -e "${YELLOW}Importing ${resource_name}...${NC}"
    echo -e "${BLUE}Resource: ${resource_address}${NC}"
    echo -e "${BLUE}ID: ${resource_id}${NC}"
    
    if terraform import "$resource_address" "$resource_id" 2>&1 | tee /tmp/import_output.log; then
        echo -e "${GREEN}✓ Successfully imported ${resource_name}${NC}"
    else
        echo -e "${RED}✗ Failed to import ${resource_name}${NC}"
        echo -e "${YELLOW}Error details:${NC}"
        tail -5 /tmp/import_output.log
    fi
}

# Navigate to terraform directory
cd terraform

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}terraform.tfvars does not exist. Create it first...${NC}"
else
    echo -e "${BLUE} terraform.tfvars already exists."
fi

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init 

echo -e "\n${GREEN}Starting resource import...${NC}\n"

# Import Service Accounts
safe_import \
    "google_service_account.gke_nodes" \
    "projects/${PROJECT_ID}/serviceAccounts/${CLUSTER_NAME}-nodes@${PROJECT_ID}.iam.gserviceaccount.com" \
    "GKE Nodes Service Account"

safe_import \
    "google_service_account.secret_accessor" \
    "projects/${PROJECT_ID}/serviceAccounts/gke-secret-accessor@${PROJECT_ID}.iam.gserviceaccount.com" \
    "Secret Accessor Service Account"

# Import Secrets
safe_import \
    "google_secret_manager_secret.postgres_password" \
    "projects/${PROJECT_ID}/secrets/postgres-password" \
    "PostgreSQL Password Secret"

safe_import \
    "google_secret_manager_secret.kafka_cluster_id" \
    "projects/${PROJECT_ID}/secrets/kafka-cluster-id" \
    "Kafka Cluster ID Secret"

safe_import \
    "google_secret_manager_secret.grafana_password" \
    "projects/${PROJECT_ID}/secrets/grafana-password" \
    "Grafana Password Secret"

# Import Secret Versions (these will need manual handling)
echo -e "${YELLOW}Note: Secret versions cannot be easily imported. They will be recreated if needed.${NC}"

# Import Artifact Registry
safe_import \
    "google_artifact_registry_repository.docker_repo" \
    "projects/${PROJECT_ID}/locations/${REGION}/repositories/iot-pipeline" \
    "Artifact Registry Repository"

# Import Network Resources (if they exist)
safe_import \
    "google_compute_network.vpc" \
    "projects/${PROJECT_ID}/global/networks/iot-pipeline-network" \
    "VPC Network"

safe_import \
    "google_compute_subnetwork.subnet" \
    "projects/${PROJECT_ID}/regions/${REGION}/subnetworks/iot-pipeline-subnet" \
    "Subnet"

safe_import \
    "google_compute_router.router" \
    "projects/${PROJECT_ID}/regions/${REGION}/routers/${CLUSTER_NAME}-router" \
    "Cloud Router"

safe_import \
    "google_compute_router_nat.nat" \
    "projects/${PROJECT_ID}/regions/${REGION}/routers/${CLUSTER_NAME}-router/${CLUSTER_NAME}-nat" \
    "Cloud NAT"

# Import Firewall Rules
safe_import \
    "google_compute_firewall.allow_internal" \
    "projects/${PROJECT_ID}/global/firewalls/${CLUSTER_NAME}-allow-internal" \
    "Internal Firewall Rule"

safe_import \
    "google_compute_firewall.allow_mqtt" \
    "projects/${PROJECT_ID}/global/firewalls/${CLUSTER_NAME}-allow-mqtt" \
    "MQTT Firewall Rule"

safe_import \
    "google_compute_firewall.allow_health_check" \
    "projects/${PROJECT_ID}/global/firewalls/${CLUSTER_NAME}-allow-health-check" \
    "Health Check Firewall Rule"

# Import GKE Cluster
safe_import \
    "google_container_cluster.primary" \
    "projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_NAME}" \
    "GKE Cluster"

# Import Node Pool
safe_import \
    "google_container_node_pool.primary_nodes" \
    "projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_NAME}/nodePools/${CLUSTER_NAME}-primary-pool" \
    "Primary Node Pool"

echo -e "\n${GREEN}=========================================="
echo "Import process completed!"
echo "==========================================${NC}"