#!/bin/bash
# Script to clean up existing GCP resources that conflict with Terraform
# WARNING: This will DELETE resources. Use with caution!

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-prj-mtp-aiot-dip}"
REGION="${GCP_REGION:-europe-north1}"
ZONE="${GCP_ZONE:-europe-north1-a}"
CLUSTER_NAME="${GKE_CLUSTER_NAME:-iot-pipeline-cluster}"

echo -e "${RED}=========================================="
echo "WARNING: Resource Cleanup Script"
echo "==========================================${NC}"
echo -e "${YELLOW}This script will DELETE existing GCP resources${NC}"
echo -e "${YELLOW}that conflict with the Terraform configuration.${NC}"
echo ""
read -p "Are you absolutely sure you want to continue? (type 'yes' to confirm): " -r
echo

if [[ ! $REPLY == "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo -e "${YELLOW}Starting cleanup...${NC}\n"

# Function to safely delete a resource
safe_delete() {
    local resource_type=$1
    local resource_name=$2
    local delete_command=$3
    
    echo -e "${YELLOW}Checking ${resource_type}: ${resource_name}${NC}"
    
    if eval "$delete_command" 2>/dev/null; then
        echo -e "${GREEN}✓ Deleted ${resource_name}${NC}"
    else
        echo -e "${YELLOW}⚠ ${resource_name} not found or already deleted${NC}"
    fi
}

# Delete in reverse order of dependencies

# 1. Delete Node Pools (must be deleted before cluster)
echo -e "\n${YELLOW}=== Deleting Node Pools ===${NC}"
safe_delete "Node Pool" "${CLUSTER_NAME}-primary-pool" \
    "gcloud container node-pools delete ${CLUSTER_NAME}-primary-pool \
    --cluster=${CLUSTER_NAME} \
    --zone=${ZONE} \
    --project=${PROJECT_ID} \
    --quiet"

# 2. Delete GKE Cluster
echo -e "\n${YELLOW}=== Deleting GKE Cluster ===${NC}"
safe_delete "GKE Cluster" "${CLUSTER_NAME}" \
    "gcloud container clusters delete ${CLUSTER_NAME} \
    --zone=${ZONE} \
    --project=${PROJECT_ID} \
    --quiet"

# 3. Delete Firewall Rules
echo -e "\n${YELLOW}=== Deleting Firewall Rules ===${NC}"
safe_delete "Firewall Rule" "${CLUSTER_NAME}-allow-internal" \
    "gcloud compute firewall-rules delete ${CLUSTER_NAME}-allow-internal \
    --project=${PROJECT_ID} \
    --quiet"

safe_delete "Firewall Rule" "${CLUSTER_NAME}-allow-mqtt" \
    "gcloud compute firewall-rules delete ${CLUSTER_NAME}-allow-mqtt \
    --project=${PROJECT_ID} \
    --quiet"

safe_delete "Firewall Rule" "${CLUSTER_NAME}-allow-health-check" \
    "gcloud compute firewall-rules delete ${CLUSTER_NAME}-allow-health-check \
    --project=${PROJECT_ID} \
    --quiet"

# 4. Delete Cloud NAT
echo -e "\n${YELLOW}=== Deleting Cloud NAT ===${NC}"
safe_delete "Cloud NAT" "${CLUSTER_NAME}-nat" \
    "gcloud compute routers nats delete ${CLUSTER_NAME}-nat \
    --router=${CLUSTER_NAME}-router \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --quiet"

# 5. Delete Cloud Router
echo -e "\n${YELLOW}=== Deleting Cloud Router ===${NC}"
safe_delete "Cloud Router" "${CLUSTER_NAME}-router" \
    "gcloud compute routers delete ${CLUSTER_NAME}-router \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --quiet"

# 6. Delete Subnet
echo -e "\n${YELLOW}=== Deleting Subnet ===${NC}"
safe_delete "Subnet" "iot-pipeline-subnet" \
    "gcloud compute networks subnets delete iot-pipeline-subnet \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --quiet"

# 7. Delete VPC Network
echo -e "\n${YELLOW}=== Deleting VPC Network ===${NC}"
safe_delete "VPC Network" "iot-pipeline-network" \
    "gcloud compute networks delete iot-pipeline-network \
    --project=${PROJECT_ID} \
    --quiet"

# 8. Delete Artifact Registry (Optional - may want to keep images)
echo -e "\n${YELLOW}=== Artifact Registry ===${NC}"
read -p "Delete Artifact Registry (will lose all images)? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    safe_delete "Artifact Registry" "iot-pipeline" \
        "gcloud artifacts repositories delete iot-pipeline \
        --location=${REGION} \
        --project=${PROJECT_ID} \
        --quiet"
fi

# 9. Delete Secrets (Optional - contains sensitive data)
echo -e "\n${YELLOW}=== Secrets ===${NC}"
read -p "Delete Secret Manager secrets? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    safe_delete "Secret" "postgres-password" \
        "gcloud secrets delete postgres-password \
        --project=${PROJECT_ID} \
        --quiet"
    
    safe_delete "Secret" "kafka-cluster-id" \
        "gcloud secrets delete kafka-cluster-id \
        --project=${PROJECT_ID} \
        --quiet"
    
    safe_delete "Secret" "grafana-password" \
        "gcloud secrets delete grafana-password \
        --project=${PROJECT_ID} \
        --quiet"
fi

# 10. Delete Service Accounts (Optional - may have IAM bindings)
echo -e "\n${YELLOW}=== Service Accounts ===${NC}"
read -p "Delete service accounts? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    safe_delete "Service Account" "${CLUSTER_NAME}-nodes" \
        "gcloud iam service-accounts delete ${CLUSTER_NAME}-nodes@${PROJECT_ID}.iam.gserviceaccount.com \
        --project=${PROJECT_ID} \
        --quiet"
    
    safe_delete "Service Account" "gke-secret-accessor" \
        "gcloud iam service-accounts delete gke-secret-accessor@${PROJECT_ID}.iam.gserviceaccount.com \
        --project=${PROJECT_ID} \
        --quiet"
fi

echo -e "\n${GREEN}=========================================="
echo "Cleanup completed!"
echo "==========================================${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Verify all resources are deleted"
echo "2. Run 'terraform plan' to see what will be created"
echo "3. Run 'terraform apply' to create fresh resources"