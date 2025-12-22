#!/bin/bash
# Script to intelligently import existing GCP resources into Terraform state
# This script checks if resources exist before attempting import

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
echo "Intelligent Import of Existing GCP Resources"
echo "==========================================${NC}"

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform is not installed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Terraform is installed${NC}"

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

# Navigate to terraform directory
cd terraform

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}terraform.tfvars does not exist. Create it first...${NC}"
    exit 1
fi

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init 

echo -e "\n${GREEN}Starting intelligent resource import...${NC}\n"

# Function to check if resource exists in GCP
check_resource_exists() {
    local resource_type=$1
    local resource_identifier=$2
    
    case $resource_type in
        "service_account")
            gcloud iam service-accounts describe "$resource_identifier" \
                --project=${PROJECT_ID} &>/dev/null
            return $?
            ;;
        "secret")
            gcloud secrets describe "$resource_identifier" \
                --project=${PROJECT_ID} &>/dev/null
            return $?
            ;;
        "artifact_registry")
            gcloud artifacts repositories describe "$resource_identifier" \
                --location=${REGION} \
                --project=${PROJECT_ID} &>/dev/null
            return $?
            ;;
        "vpc")
            gcloud compute networks describe "$resource_identifier" \
                --project=${PROJECT_ID} &>/dev/null
            return $?
            ;;
        "subnet")
            gcloud compute networks subnets describe "$resource_identifier" \
                --region=${REGION} \
                --project=${PROJECT_ID} &>/dev/null
            return $?
            ;;
        "router")
            gcloud compute routers describe "$resource_identifier" \
                --region=${REGION} \
                --project=${PROJECT_ID} &>/dev/null
            return $?
            ;;
        "nat")
            gcloud compute routers nats describe "$resource_identifier" \
                --router="$3" \
                --region=${REGION} \
                --project=${PROJECT_ID} &>/dev/null
            return $?
            ;;
        "firewall")
            gcloud compute firewall-rules describe "$resource_identifier" \
                --project=${PROJECT_ID} &>/dev/null
            return $?
            ;;
        "gke_cluster")
            gcloud container clusters describe "$resource_identifier" \
                --zone=${ZONE} \
                --project=${PROJECT_ID} &>/dev/null
            return $?
            ;;
        "node_pool")
            gcloud container node-pools describe "$resource_identifier" \
                --cluster="$3" \
                --zone=${ZONE} \
                --project=${PROJECT_ID} &>/dev/null
            return $?
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to check if resource is in Terraform state
check_in_terraform_state() {
    local resource_address=$1
    terraform state show "$resource_address" &>/dev/null
    return $?
}

# Function to safely import a resource
safe_import() {
    local resource_type=$1
    local resource_address=$2
    local resource_id=$3
    local resource_name=$4
    local additional_param=$5
    
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Processing: ${resource_name}${NC}"
    
    # Check if resource is already in Terraform state
    if check_in_terraform_state "$resource_address"; then
        echo -e "${GREEN}✓ ${resource_name} already in Terraform state${NC}"
        return 0
    fi
    
    # Check if resource exists in GCP
    if check_resource_exists "$resource_type" "$resource_id" "$additional_param"; then
        echo -e "${BLUE}→ Resource exists in GCP, importing...${NC}"
        
        if terraform import "$resource_address" "$resource_id" 2>&1 | tee /tmp/import_output.log; then
            echo -e "${GREEN}✓ Successfully imported ${resource_name}${NC}"
            return 0
        else
            echo -e "${RED}✗ Failed to import ${resource_name}${NC}"
            echo -e "${YELLOW}Error details:${NC}"
            tail -5 /tmp/import_output.log
            return 1
        fi
    else
        echo -e "${YELLOW}⊘ Resource does not exist in GCP (will be created by Terraform)${NC}"
        return 0
    fi
}

# Import Service Accounts
echo -e "\n${BLUE}=== Service Accounts ===${NC}"

safe_import \
    "service_account" \
    "google_service_account.gke_nodes" \
    "projects/${PROJECT_ID}/serviceAccounts/${CLUSTER_NAME}-nodes@${PROJECT_ID}.iam.gserviceaccount.com" \
    "GKE Nodes Service Account"

safe_import \
    "service_account" \
    "google_service_account.secret_accessor" \
    "projects/${PROJECT_ID}/serviceAccounts/gke-secret-accessor@${PROJECT_ID}.iam.gserviceaccount.com" \
    "Secret Accessor Service Account"

# Import Secrets
echo -e "\n${BLUE}=== Secrets ===${NC}"

safe_import \
    "secret" \
    "google_secret_manager_secret.postgres_password" \
    "projects/${PROJECT_ID}/secrets/postgres-password" \
    "PostgreSQL Password Secret"

safe_import \
    "secret" \
    "google_secret_manager_secret.kafka_cluster_id" \
    "projects/${PROJECT_ID}/secrets/kafka-cluster-id" \
    "Kafka Cluster ID Secret"

safe_import \
    "secret" \
    "google_secret_manager_secret.grafana_password" \
    "projects/${PROJECT_ID}/secrets/grafana-password" \
    "Grafana Password Secret"

# Import Artifact Registry
echo -e "\n${BLUE}=== Artifact Registry ===${NC}"

safe_import \
    "artifact_registry" \
    "google_artifact_registry_repository.docker_repo" \
    "projects/${PROJECT_ID}/locations/${REGION}/repositories/iot-pipeline" \
    "Artifact Registry Repository"

# Import Network Resources
echo -e "\n${BLUE}=== Network Resources ===${NC}"

safe_import \
    "vpc" \
    "google_compute_network.vpc" \
    "projects/${PROJECT_ID}/global/networks/iot-pipeline-network" \
    "VPC Network"

safe_import \
    "subnet" \
    "google_compute_subnetwork.subnet" \
    "projects/${PROJECT_ID}/regions/${REGION}/subnetworks/iot-pipeline-subnet" \
    "Subnet"

safe_import \
    "router" \
    "google_compute_router.router" \
    "projects/${PROJECT_ID}/regions/${REGION}/routers/${CLUSTER_NAME}-router" \
    "Cloud Router"

safe_import \
    "nat" \
    "google_compute_router_nat.nat" \
    "projects/${PROJECT_ID}/regions/${REGION}/routers/${CLUSTER_NAME}-router/${CLUSTER_NAME}-nat" \
    "Cloud NAT" \
    "${CLUSTER_NAME}-router"

# Import Firewall Rules
echo -e "\n${BLUE}=== Firewall Rules ===${NC}"

safe_import \
    "firewall" \
    "google_compute_firewall.allow_internal" \
    "projects/${PROJECT_ID}/global/firewalls/${CLUSTER_NAME}-allow-internal" \
    "Internal Firewall Rule"

safe_import \
    "firewall" \
    "google_compute_firewall.allow_mqtt" \
    "projects/${PROJECT_ID}/global/firewalls/${CLUSTER_NAME}-allow-mqtt" \
    "MQTT Firewall Rule"

safe_import \
    "firewall" \
    "google_compute_firewall.allow_health_check" \
    "projects/${PROJECT_ID}/global/firewalls/${CLUSTER_NAME}-allow-health-check" \
    "Health Check Firewall Rule"

# Import GKE Cluster
echo -e "\n${BLUE}=== GKE Resources ===${NC}"

safe_import \
    "gke_cluster" \
    "google_container_cluster.primary" \
    "projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_NAME}" \
    "GKE Cluster"

# Import Node Pool
safe_import \
    "node_pool" \
    "google_container_node_pool.primary_nodes" \
    "projects/${PROJECT_ID}/locations/${ZONE}/clusters/${CLUSTER_NAME}/nodePools/${CLUSTER_NAME}-primary-pool" \
    "Primary Node Pool" \
    "${CLUSTER_NAME}"

echo -e "\n${GREEN}=========================================="
echo "Import process completed!"
echo "==========================================${NC}"

# Summary
echo -e "\n${BLUE}Summary:${NC}"
echo "Run 'terraform plan' to see what changes are needed"
echo "Run 'terraform apply' to sync Terraform state with GCP"