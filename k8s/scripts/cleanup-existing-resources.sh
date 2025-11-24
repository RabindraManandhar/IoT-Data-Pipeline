#!/bin/bash
# Script to intelligently clean up existing GCP resources
# This script checks if resources exist before attempting to delete them

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
echo "WARNING: Intelligent Resource Cleanup Script"
echo "==========================================${NC}"
echo -e "${YELLOW}This script will DELETE existing GCP resources.${NC}"
echo ""

# Check if running in non-interactive mode
if [ "$1" != "--yes" ] && [ "$1" != "-y" ]; then
    read -p "Are you absolutely sure you want to continue? (type 'yes' to confirm): " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

echo -e "${YELLOW}Starting intelligent cleanup...${NC}\n"

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_identifier=$2
    local additional_param=$3
    
    case $resource_type in
        "service_account")
            gcloud iam service-accounts describe "$resource_identifier" \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        "secret")
            gcloud secrets describe "$resource_identifier" \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        "artifact_registry")
            gcloud artifacts repositories describe "$resource_identifier" \
                --location=${REGION} \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        "vpc")
            gcloud compute networks describe "$resource_identifier" \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        "subnet")
            gcloud compute networks subnets describe "$resource_identifier" \
                --region=${REGION} \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        "router")
            gcloud compute routers describe "$resource_identifier" \
                --region=${REGION} \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        "nat")
            gcloud compute routers nats describe "$resource_identifier" \
                --router="$additional_param" \
                --region=${REGION} \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        "firewall")
            gcloud compute firewall-rules describe "$resource_identifier" \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        "gke_cluster")
            gcloud container clusters describe "$resource_identifier" \
                --zone=${ZONE} \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        "node_pool")
            gcloud container node-pools describe "$resource_identifier" \
                --cluster="$additional_param" \
                --zone=${ZONE} \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to safely delete a resource
safe_delete() {
    local resource_type=$1
    local resource_identifier=$2
    local delete_command=$3
    local resource_name=$4
    
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Checking: ${resource_name}${NC}"
    
    if resource_exists "$resource_type" "$resource_identifier" "$5"; then
        echo -e "${YELLOW}→ Resource exists, deleting...${NC}"
        
        if eval "$delete_command" 2>&1 | tee /tmp/delete_output.log; then
            echo -e "${GREEN}✓ Deleted ${resource_name}${NC}"
            return 0
        else
            echo -e "${RED}✗ Failed to delete ${resource_name}${NC}"
            echo -e "${YELLOW}Error details:${NC}"
            tail -5 /tmp/delete_output.log
            return 1
        fi
    else
        echo -e "${GREEN}⊘ ${resource_name} does not exist (already deleted or never created)${NC}"
        return 0
    fi
}

# Delete in reverse order of dependencies

# 1. Delete Node Pool first (if exists)
echo -e "\n${YELLOW}=== Deleting Node Pool ===${NC}"
safe_delete \
    "node_pool" \
    "${CLUSTER_NAME}-primary-pool" \
    "gcloud container node-pools delete ${CLUSTER_NAME}-primary-pool \
    --cluster=${CLUSTER_NAME} \
    --zone=${ZONE} \
    --project=${PROJECT_ID} \
    --quiet" \
    "Primary Node Pool" \
    "${CLUSTER_NAME}"

# 2. Delete GKE Cluster
echo -e "\n${YELLOW}=== Deleting GKE Cluster ===${NC}"
safe_delete \
    "gke_cluster" \
    "${CLUSTER_NAME}" \
    "gcloud container clusters delete ${CLUSTER_NAME} \
    --zone=${ZONE} \
    --project=${PROJECT_ID} \
    --quiet" \
    "GKE Cluster"

# 3. Delete Firewall Rules
echo -e "\n${YELLOW}=== Deleting Firewall Rules ===${NC}"

safe_delete \
    "firewall" \
    "${CLUSTER_NAME}-allow-internal" \
    "gcloud compute firewall-rules delete ${CLUSTER_NAME}-allow-internal \
    --project=${PROJECT_ID} \
    --quiet" \
    "Internal Firewall Rule"

safe_delete \
    "firewall" \
    "${CLUSTER_NAME}-allow-mqtt" \
    "gcloud compute firewall-rules delete ${CLUSTER_NAME}-allow-mqtt \
    --project=${PROJECT_ID} \
    --quiet" \
    "MQTT Firewall Rule"

safe_delete \
    "firewall" \
    "${CLUSTER_NAME}-allow-health-check" \
    "gcloud compute firewall-rules delete ${CLUSTER_NAME}-allow-health-check \
    --project=${PROJECT_ID} \
    --quiet" \
    "Health Check Firewall Rule"

# 4. Delete Cloud NAT
echo -e "\n${YELLOW}=== Deleting Cloud NAT ===${NC}"
safe_delete \
    "nat" \
    "${CLUSTER_NAME}-nat" \
    "gcloud compute routers nats delete ${CLUSTER_NAME}-nat \
    --router=${CLUSTER_NAME}-router \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --quiet" \
    "Cloud NAT" \
    "${CLUSTER_NAME}-router"

# 5. Delete Cloud Router
echo -e "\n${YELLOW}=== Deleting Cloud Router ===${NC}"
safe_delete \
    "router" \
    "${CLUSTER_NAME}-router" \
    "gcloud compute routers delete ${CLUSTER_NAME}-router \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --quiet" \
    "Cloud Router"

# 6. Delete Subnet
echo -e "\n${YELLOW}=== Deleting Subnet ===${NC}"
safe_delete \
    "subnet" \
    "iot-pipeline-subnet" \
    "gcloud compute networks subnets delete iot-pipeline-subnet \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --quiet" \
    "Subnet"

# 7. Delete VPC Network
echo -e "\n${YELLOW}=== Deleting VPC Network ===${NC}"
safe_delete \
    "vpc" \
    "iot-pipeline-network" \
    "gcloud compute networks delete iot-pipeline-network \
    --project=${PROJECT_ID} \
    --quiet" \
    "VPC Network"

# 8. Delete Artifact Registry (Optional)
echo -e "\n${YELLOW}=== Artifact Registry ===${NC}"

if [ "$1" != "--keep-registry" ]; then
    if [ "$2" != "--yes" ] && [ "$2" != "-y" ]; then
        read -p "Delete Artifact Registry (will lose all images)? (y/n): " -n 1 -r
        echo
    else
        REPLY="y"
    fi
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        safe_delete \
            "artifact_registry" \
            "iot-pipeline" \
            "gcloud artifacts repositories delete iot-pipeline \
            --location=${REGION} \
            --project=${PROJECT_ID} \
            --quiet" \
            "Artifact Registry"
    else
        echo -e "${BLUE}⊙ Keeping Artifact Registry${NC}"
    fi
else
    echo -e "${BLUE}⊙ Keeping Artifact Registry (--keep-registry flag)${NC}"
fi

# 9. Delete Secrets (Optional)
echo -e "\n${YELLOW}=== Secrets ===${NC}"

if [ "$1" != "--keep-secrets" ]; then
    if [ "$2" != "--yes" ] && [ "$2" != "-y" ] && [ "$1" != "--yes" ]; then
        read -p "Delete Secret Manager secrets? (y/n): " -n 1 -r
        echo
    else
        REPLY="y"
    fi
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        safe_delete \
            "secret" \
            "postgres-password" \
            "gcloud secrets delete postgres-password \
            --project=${PROJECT_ID} \
            --quiet" \
            "PostgreSQL Password Secret"
        
        safe_delete \
            "secret" \
            "kafka-cluster-id" \
            "gcloud secrets delete kafka-cluster-id \
            --project=${PROJECT_ID} \
            --quiet" \
            "Kafka Cluster ID Secret"
        
        safe_delete \
            "secret" \
            "grafana-password" \
            "gcloud secrets delete grafana-password \
            --project=${PROJECT_ID} \
            --quiet" \
            "Grafana Password Secret"
    else
        echo -e "${BLUE}⊙ Keeping secrets${NC}"
    fi
else
    echo -e "${BLUE}⊙ Keeping secrets (--keep-secrets flag)${NC}"
fi

# 10. Delete Service Accounts (Optional)
echo -e "\n${YELLOW}=== Service Accounts ===${NC}"

if [ "$1" != "--keep-service-accounts" ]; then
    if [ "$2" != "--yes" ] && [ "$2" != "-y" ] && [ "$1" != "--yes" ]; then
        read -p "Delete service accounts? (y/n): " -n 1 -r
        echo
    else
        REPLY="y"
    fi
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        safe_delete \
            "service_account" \
            "${CLUSTER_NAME}-nodes@${PROJECT_ID}.iam.gserviceaccount.com" \
            "gcloud iam service-accounts delete ${CLUSTER_NAME}-nodes@${PROJECT_ID}.iam.gserviceaccount.com \
            --project=${PROJECT_ID} \
            --quiet" \
            "GKE Nodes Service Account"
        
        safe_delete \
            "service_account" \
            "gke-secret-accessor@${PROJECT_ID}.iam.gserviceaccount.com" \
            "gcloud iam service-accounts delete gke-secret-accessor@${PROJECT_ID}.iam.gserviceaccount.com \
            --project=${PROJECT_ID} \
            --quiet" \
            "Secret Accessor Service Account"
    else
        echo -e "${BLUE}⊙ Keeping service accounts${NC}"
    fi
else
    echo -e "${BLUE}⊙ Keeping service accounts (--keep-service-accounts flag)${NC}"
fi

echo -e "\n${GREEN}=========================================="
echo "Cleanup process completed!"
echo "==========================================${NC}"

# Show summary
echo -e "\n${BLUE}Summary:${NC}"
echo "Resources have been intelligently cleaned up"
echo "Only existing resources were deleted"
echo ""
echo -e "${YELLOW}Flags available:${NC}"
echo "  --yes                      Skip all confirmations"
echo "  --keep-registry            Keep Artifact Registry"
echo "  --keep-secrets             Keep Secret Manager secrets"
echo "  --keep-service-accounts    Keep service accounts"
echo ""
echo "Example: ./cleanup-existing-resources.sh --yes --keep-registry"