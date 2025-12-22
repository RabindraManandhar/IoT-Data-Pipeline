#!/bin/bash
# Intelligent GKE Deployment Script with comprehensive error handling
# This script handles the complete deployment lifecycle for the IoT Data Pipeline

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-prj-mtp-aiot-dip}"
REGION="${GCP_REGION:-europe-north1}"
ZONE="${GCP_ZONE:-europe-north1-a}"
CLUSTER_NAME="${GKE_CLUSTER_NAME:-iot-pipeline-cluster}"
ARTIFACT_REPO="${ARTIFACT_REPO:-iot-pipeline}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Logging
mkdir -p logs
LOG_FILE="${PROJECT_ROOT}/gke/logs/deployment-$(date +%Y%m%d-%H%M%S).log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2>&1

echo -e "${CYAN}=========================================="
echo "IoT Data Pipeline - GKE Deployment"
echo "==========================================${NC}"
echo -e "Log file: ${LOG_FILE}\n"

# Function to print section headers
print_section() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Function to check command availability
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}❌ $1 is not installed${NC}"
        echo -e "${YELLOW}Please install $1 and try again${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ $1 is available${NC}"
}

# Function to check if resource exists in GCP
resource_exists() {
    local resource_type=$1
    local resource_identifier=$2
    local additional_param=$3
    
    case $resource_type in
        "gke_cluster")
            gcloud container clusters describe "$resource_identifier" \
                --zone=${ZONE} \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        "artifact_registry")
            gcloud artifacts repositories describe "$resource_identifier" \
                --location=${REGION} \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        "secret")
            gcloud secrets describe "$resource_identifier" \
                --project=${PROJECT_ID} &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to wait for cluster to be ready
wait_for_cluster() {
    local max_attempts=60
    local attempt=1
    
    echo -e "${YELLOW}Waiting for cluster to be ready...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        if gcloud container clusters describe ${CLUSTER_NAME} \
            --zone=${ZONE} \
            --project=${PROJECT_ID} \
            --format="value(status)" 2>/dev/null | grep -q "RUNNING"; then
            echo -e "${GREEN}✅ Cluster is ready!${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}⏳ Attempt $attempt/$max_attempts - Cluster not ready yet...${NC}"
        sleep 10
        ((attempt++))
    done
    
    echo -e "${RED}❌ Cluster failed to become ready within expected time${NC}"
    return 1
}

# Function to wait for node pool to be ready
wait_for_node_pool() {
    local pool_name=$1
    local max_attempts=60
    local attempt=1
    
    echo -e "${YELLOW}Waiting for node pool ${pool_name} to be ready...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        local status=$(gcloud container node-pools describe ${pool_name} \
            --cluster=${CLUSTER_NAME} \
            --zone=${ZONE} \
            --project=${PROJECT_ID} \
            --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$status" = "RUNNING" ]; then
            echo -e "${GREEN}✅ Node pool is ready!${NC}"
            return 0
        elif [ "$status" = "ERROR" ]; then
            echo -e "${RED}❌ Node pool entered ERROR state${NC}"
            return 1
        fi
        
        echo -e "${YELLOW}⏳ Attempt $attempt/$max_attempts - Node pool status: ${status}${NC}"
        sleep 10
        ((attempt++))
    done
    
    echo -e "${RED}❌ Node pool failed to become ready${NC}"
    return 1
}

# Parse command line arguments
CLEAN_START=false
SKIP_TERRAFORM=false
SKIP_BUILD=false
SKIP_DEPLOY=false
IMPORT_EXISTING=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_START=true
            shift
            ;;
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --skip-deploy)
            SKIP_DEPLOY=true
            shift
            ;;
        --import)
            IMPORT_EXISTING=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clean            Perform clean start (delete existing resources)"
            echo "  --skip-terraform   Skip Terraform infrastructure setup"
            echo "  --skip-build       Skip Docker image building"
            echo "  --skip-deploy      Skip Kubernetes deployment"
            echo "  --import           Import existing resources into Terraform"
            echo "  --help             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                           # Full deployment"
            echo "  $0 --clean                   # Clean start"
            echo "  $0 --import                  # Import existing resources"
            echo "  $0 --skip-build --skip-deploy # Only setup infrastructure"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Step 1: Prerequisites Check
print_section "Step 1: Checking Prerequisites"

check_command "gcloud"
check_command "terraform"
check_command "kubectl"
check_command "docker"

# Check gcloud authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
    echo -e "${RED}❌ Not authenticated with gcloud${NC}"
    echo -e "${YELLOW}Please run: gcloud auth login${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Authenticated with gcloud${NC}"

# Check Docker authentication for Artifact Registry
if ! gcloud auth print-access-token &>/dev/null; then
    echo -e "${YELLOW}⚠️  Docker not configured for Artifact Registry${NC}"
    echo -e "${YELLOW}Configuring Docker authentication...${NC}"
    gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet
    echo -e "${GREEN}✅ Docker configured${NC}"
else
    echo -e "${GREEN}✅ Docker authentication configured${NC}"
fi

# Set project
gcloud config set project ${PROJECT_ID} --quiet
echo -e "${GREEN}✅ Project set to ${PROJECT_ID}${NC}"

# Step 2: Clean Start (if requested)
if [ "$CLEAN_START" = true ]; then
    print_section "Step 2: Clean Start - Removing Existing Resources"
    
    echo -e "${YELLOW}⚠️  This will delete all existing resources!${NC}"
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    echo
    
    if [[ $REPLY == "yes" ]]; then
        if [ -f "${SCRIPT_DIR}/cleanup-existing-resources.sh" ]; then
            bash "${SCRIPT_DIR}/cleanup-existing-resources.sh" --yes
        else
            echo -e "${RED}❌ cleanup-existing-resources.sh not found${NC}"
            exit 1
        fi
        
        # Clean Terraform state
        echo -e "${YELLOW}Cleaning Terraform state...${NC}"
        cd "${PROJECT_ROOT}/gke/terraform"
        rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
        echo -e "${GREEN}✅ Terraform state cleaned${NC}"
    else
        echo -e "${YELLOW}Clean start cancelled${NC}"
        exit 0
    fi
fi

# Step 3: Import Existing Resources (if requested)
if [ "$IMPORT_EXISTING" = true ]; then
    print_section "Step 3: Importing Existing Resources"
    
    if [ -f "${SCRIPT_DIR}/import-existing-resources.sh" ]; then
        bash "${SCRIPT_DIR}/import-existing-resources.sh"
    else
        echo -e "${RED}❌ import-existing-resources.sh not found${NC}"
        exit 1
    fi
fi

# Step 4: Terraform Infrastructure Setup
if [ "$SKIP_TERRAFORM" = false ]; then
    print_section "Step 4: Setting Up Infrastructure with Terraform"
    
    cd "${PROJECT_ROOT}/gke/terraform"
    
    # Check if terraform.tfvars exists
    if [ ! -f "terraform.tfvars" ]; then
        echo -e "${RED}❌ terraform.tfvars not found${NC}"
        echo -e "${YELLOW}Please create terraform.tfvars from terraform.tfvars.example${NC}"
        exit 1
    fi
    
    # Initialize Terraform
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init
    echo -e "${GREEN}✅ Terraform initialized${NC}"
    
    # Validate configuration
    echo -e "${YELLOW}Validating Terraform configuration...${NC}"
    terraform validate
    echo -e "${GREEN}✅ Configuration valid${NC}"
    
    # Plan
    echo -e "${YELLOW}Creating Terraform plan...${NC}"
    terraform plan -out=tfplan
    echo -e "${GREEN}✅ Plan created${NC}"
    
    # Apply
    echo -e "${YELLOW}Applying Terraform configuration...${NC}"
    terraform apply tfplan
    echo -e "${GREEN}✅ Infrastructure deployed${NC}"
    
    # Wait for cluster to be ready
    if resource_exists "gke_cluster" "${CLUSTER_NAME}"; then
        wait_for_cluster
        
        # Check node pool status
        if resource_exists "node_pool" "${CLUSTER_NAME}-primary-pool" "${CLUSTER_NAME}"; then
            wait_for_node_pool "${CLUSTER_NAME}-primary-pool"
        fi
    fi
    
    cd "${PROJECT_ROOT}"
else
    echo -e "${BLUE}⊙ Skipping Terraform infrastructure setup${NC}"
fi

# Step 5: Configure kubectl
print_section "Step 5: Configuring kubectl"

if resource_exists "gke_cluster" "${CLUSTER_NAME}"; then
    echo -e "${YELLOW}Getting GKE credentials...${NC}"
    gcloud container clusters get-credentials ${CLUSTER_NAME} \
        --zone=${ZONE} \
        --project=${PROJECT_ID}
    echo -e "${GREEN}✅ kubectl configured${NC}"
    
    # Verify cluster access
    echo -e "${YELLOW}Verifying cluster access...${NC}"
    kubectl cluster-info
    echo -e "${GREEN}✅ Cluster accessible${NC}"
    
    # Check nodes
    echo -e "${YELLOW}Checking cluster nodes...${NC}"
    kubectl get nodes
else
    echo -e "${RED}❌ GKE cluster not found${NC}"
    echo -e "${YELLOW}Please run Terraform to create the cluster first${NC}"
    exit 1
fi

# Step 6: Build and Push Docker Images
if [ "$SKIP_BUILD" = false ]; then
    print_section "Step 6: Building and Pushing Docker Images"
    
    if [ -f "${SCRIPT_DIR}/build-images.sh" ]; then
        bash "${SCRIPT_DIR}/build-images.sh"
    else
        echo -e "${RED}❌ build-images.sh not found${NC}"
        exit 1
    fi
else
    echo -e "${BLUE}⊙ Skipping Docker image building${NC}"
fi

# Step 7: Deploy Kubernetes Resources
if [ "$SKIP_DEPLOY" = false ]; then
    print_section "Step 7: Deploying Kubernetes Resources"
    
    cd "${PROJECT_ROOT}"
    
    # Create namespaces
    echo -e "${YELLOW}Creating namespaces...${NC}"
    kubectl apply -f gke/namespace/
    echo -e "${GREEN}✅ Namespace created${NC}"
    
    # Deploy storage classes and PVCs
    echo -e "${YELLOW}Deploying storage resources...${NC}"
    kubectl apply -f gke/storage/
    echo -e "${GREEN}✅ Storage resources deployed${NC}"
    
    # Deploy ConfigMaps and Secrets
    echo -e "${YELLOW}Deploying ConfigMaps...${NC}"
    kubectl apply -f gke/config/
    echo -e "${GREEN}✅ ConfigMaps and secrets deployed${NC}"
    
    # Deploy infrastructure services (Kafka, TimescaleDB, etc.)
    echo -e "${YELLOW}Deploying infrastructure services...${NC}"
    
    # Deploy in order
    echo -e "${CYAN}  → Deploying Kafka...${NC}"
    kubectl apply -f gke/kafka/

    # Wait for Kafka to be ready
    echo -e "${YELLOW}Waiting for Kafka services to be ready...${NC}"
    sleep 30

    echo -e "${YELLOW}Checking Kafka pods...${NC}"
    kubectl wait --for=condition=ready pod -l app=kafka -n data --timeout=300s || true
    
    echo -e "${CYAN}  → Deploying TimescaleDB...${NC}"
    kubectl apply -f gke/timescaledb/
    
    # Wait for TimescaleDB to be ready
    echo -e "${YELLOW}Waiting for TimescaleDB services to be ready...${NC}"
    sleep 30
    
    echo -e "${YELLOW}Checking TimescaleDB pods...${NC}"
    kubectl wait --for=condition=ready pod -l app=timescaledb -n data --timeout=300s || true

    echo -e "${CYAN}  → Deploying Schema Registry...${NC}"
    kubectl apply -f gke/schema-registry/
    
    echo -e "${CYAN}  → Deploying Mosquitto...${NC}"
    kubectl apply -f gke/mosquitto/
    
    echo -e "${GREEN}✅ Infrastructure services deployed${NC}"
    
    # Deploy application services
    echo -e "${YELLOW}Deploying application services...${NC}"
    kubectl apply -f gke/app-services/services.yaml
    
    echo -e "${CYAN}  → Deploying RuuviTag Adapter...${NC}"
    kubectl apply -f gke/app-services/ruuvitag-adapter-deployment.yaml
    
    echo -e "${CYAN}  → Deploying Consumer...${NC}"
    kubectl apply -f gke/app-services/kafka-consumer-deployment.yaml
    
    echo -e "${CYAN}  → Deploying Sink...${NC}"
    kubectl apply -f gke/app-services/timescaledb-sink-deployment.yaml
    
    echo -e "${GREEN}✅ Application services deployed${NC}"
    
    # Deploy monitoring stack
    echo -e "${YELLOW}Deploying monitoring stack...${NC}"
    
    echo -e "${CYAN}  → Deploying Prometheus...${NC}"
    kubectl apply -f gke/monitoring/prometheus/
    
    echo -e "${CYAN}  → Deploying Grafana...${NC}"
    kubectl apply -f gke/monitoring/grafana/
    
    echo -e "${CYAN}  → Deploying AlertManager...${NC}"
    kubectl apply -f gke/monitoring/alertmanager/

    echo -e "${CYAN}  → Deploying Exporters...${NC}"
    kubectl apply -f gke/monitoring/exporters/
    
    echo -e "${GREEN}✅ Monitoring stack deployed${NC}"
    
else
    echo -e "${BLUE}⊙ Skipping Kubernetes deployment${NC}"
fi

# Step 8: Deployment Summary
print_section "Step 8: Deployment Summary"

echo -e "${GREEN}✅ Deployment completed successfully!${NC}\n"

# Show cluster information
echo -e "${CYAN}Cluster Information:${NC}"
echo "  Project: ${PROJECT_ID}"
echo "  Region: ${REGION}"
echo "  Zone: ${ZONE}"
echo "  Cluster: ${CLUSTER_NAME}"
echo ""

# Show node status
echo -e "${CYAN}Node Status:${NC}"
kubectl get nodes -o wide
echo ""

# Show pod status across all namespaces
echo -e "${CYAN}Pod Status:${NC}"
kubectl get pods --all-namespaces
echo ""

# Show services
echo -e "${CYAN}Services:${NC}"
kubectl get services --all-namespaces
echo ""

# Show storage information
echo -e "${CYAN}Persistent Volumes:${NC}"
kubectl get pv,pvc --all-namespaces
echo ""

# Useful commands
echo -e "${CYAN}Useful Commands:${NC}"
echo "  Check pod logs:        kubectl logs <pod-name> -n <namespace>"
echo "  Port forward Grafana:  kubectl port-forward svc/grafana 3000:3000 -n monitoring"
echo "  Scale deployment:      kubectl scale deployment <name> --replicas=<count> -n <namespace>"
echo "  Delete deployment:     kubectl delete -f gke/"
echo ""

# Save endpoints to file
ENDPOINTS_FILE="${PROJECT_ROOT}/gke/deployment-endpoints.txt"
echo "Deployment Endpoints" > ${ENDPOINTS_FILE}
echo "====================" >> ${ENDPOINTS_FILE}
echo "" >> ${ENDPOINTS_FILE}
echo "Generated: $(date)" >> ${ENDPOINTS_FILE}
echo "" >> ${ENDPOINTS_FILE}

echo -e "${GREEN}Endpoints saved to: ${ENDPOINTS_FILE}${NC}"
echo -e "${GREEN}Deployment log saved to: ${LOG_FILE}${NC}"

# Final notes
echo -e "\n${YELLOW}Important Notes:${NC}"
echo "  1. Some services may take a few minutes to fully initialize"
echo "  2. Check pod status with: kubectl get pods --all-namespaces"
echo "  3. Access Grafana at the ingress endpoint (default password in secrets)"
echo "  4. Monitor cluster with: kubectl top nodes && kubectl top pods --all-namespaces"
echo ""

echo -e "${GREEN}=========================================="
echo "Deployment Completed Successfully!"
echo "==========================================${NC}"