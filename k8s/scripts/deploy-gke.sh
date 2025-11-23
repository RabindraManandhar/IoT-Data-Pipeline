#!/bin/bash
# Comprehensive GKE Deployment Script for IoT Data Pipeline

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-prj-mtp-aiot-dip}"
CLUSTER_NAME="${GKE_CLUSTER_NAME:-iot-pipeline-cluster}"
REGION="${GCP_REGION:-europe-north1}"
ZONE="${GCP_ZONE:-europe-north1-a}"
NAMESPACE="iot-pipeline"
REPOSITORY="iot-pipeline"

echo -e "${GREEN}=========================================="
echo "IoT Data Pipeline - GKE Deployment"
echo "==========================================${NC}"
echo -e "Project: ${BLUE}${PROJECT_ID}${NC}"
echo -e "Cluster: ${BLUE}${CLUSTER_NAME}${NC}"
echo -e "Region: ${BLUE}${REGION}${NC}"
echo -e "Zone: ${BLUE}${ZONE}${NC}"
echo ""

# Function to display menu
show_menu() {
    echo -e "${BLUE}Deployment Options:${NC}"
    echo "  1. Full deployment (Infrastructure + Applications)"
    echo "  2. Infrastructure only (Terraform)"
    echo "  3. Build and push Docker images"
    echo "  4. Deploy Kubernetes manifests only"
    echo "  5. Setup monitoring and logging"
    echo "  6. Status check"
    echo "  7. Port forwarding setup"
    echo "  8. Cleanup deployment"
    echo "  9. Exit"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"
    
    # Check for required tools
    local tools=("gcloud" "kubectl" "terraform" "docker")
    for tool in "${tools[@]}"; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}❌ $tool is not installed${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ $tool is installed${NC}"
    done
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        echo -e "${RED}❌ Not authenticated with gcloud${NC}"
        echo "Please run: gcloud auth login"
        exit 1
    fi
    echo -e "${GREEN}✅ Authenticated with gcloud${NC}"
    
    # Set project
    gcloud config set project ${PROJECT_ID}
    echo -e "${GREEN}✅ Project set to ${PROJECT_ID}${NC}"

    # Enable required APIs
    echo -e "${YELLOW}Enabling required Google Cloud APIs...${NC}"
    gcloud services enable \
    container.googleapis.com \
    compute.googleapis.com \
    artifactregistry.googleapis.com \
    secretmanager.googleapis.com \
    monitoring.googleapis.com \
    logging.googleapis.com \
    cloudtrace.googleapis.com \
    clouderrorreporting.googleapis.com \
    --project=${PROJECT_ID}
    echo -e "${GREEN}✅ APIs enabled${NC}"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    echo -e "${BLUE}Deploying infrastructure with Terraform...${NC}"
    
    cd terraform
    
    # Initialize Terraform
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init 
    
    # Generate Terraform plan
    echo -e "${YELLOW}Generating Terraform plan...${NC}"
    terraform plan -out=tfplan


    # Apply Terraform configuration
    read -p "Apply Terraform configuration? (yes/no) " -r
    if [[ $REPLY == "yes" ]]; then
        echo -e "${YELLOW}Applying Terraform configuration...${NC}"
        terraform apply tfplan
        echo -e "${GREEN}✅ Terraform infrastructure deployed${NC}"
    else
        echo -e "${YELLOW}Skipping Terraform infrastructure deployment${NC}"
        cd ..
        return
    fi
    
    cd ..

    # Configure kubectl
    echo -e "${BLUE}Configuring kubectl...${NC}"
    gcloud container clusters get-credentials ${CLUSTER_NAME} \
        --zone ${ZONE} \
        --project ${PROJECT_ID}
    
    echo -e "${GREEN}✅ kubectl configured${NC}"
}

# Build and push Docker images
build_and_push_images() {
    echo -e "${BLUE}Building and Pushing Docker Images...${NC}"

    chmod +x k8s/scripts/build-and-push-images.sh
    ./k8s/scripts/build-and-push-images.sh

    echo -e "{GREEN}✅ Docker Images built and pushed successfully${NC}"
}

# Create Kubernetes secrets
create_secrets() {
    echo -e "${BLUE}Creating Kubernetes secrets...${NC}"
    
    chmod +x k8s/scripts/create-k8s-secrets.sh
    ./k8s/scripts/create-k8s-secrets.sh
    
    echo -e "${GREEN}✅ Secrets created${NC}"
}

# Deploy Kubernetes manifests
deploy_kubernetes() {
    echo -e "${BLUE}Deploying Kubernetes manifests...${NC}"

    # Update image references in manifests
    echo -e "${BLUE}Updating image references...${NC}"
    for file in k8s/app-services/*-deployment.yaml; do
        # This is a simple replacement - in production, use kustomize or helm
        sed -i.bak "s|image: rabindramdr/|image: ${REGISTRY_URL}/|g" "$file"
        sed -i.bak "s|:v1.0.0|:${IMAGE_TAG}|g" "$file"
    done
    echo -e "${GREEN}✅ Image references updated${NC}"
    
    # Create namespace
    echo -e "${YELLOW} Creating namespace...${NC}"
    kubectl apply -f k8s/namespace/namespace.yaml
    
    # Deploy in order
    echo -e "${YELLOW}Deploying storage...${NC}"
    kubectl apply -f k8s/storage/
    
    echo -e "${YELLOW}Deploying configs...${NC}"
    kubectl apply -f k8s/config/
    
    echo -e "${YELLOW}Deploying RBAC...${NC}"
    kubectl apply -f k8s/rbac/
    
    echo -e "${YELLOW}Deploying Kafka...${NC}"
    kubectl apply -f k8s/kafka/
    echo "Waiting for Kafka pods to be ready (this may take 3-5 minutes)..."
    kubectl wait --for=condition=ready pod -l app=kafka -n ${NAMESPACE} --timeout=600s || true
    
    echo -e "${YELLOW}Deploying Schema Registry...${NC}"
    kubectl apply -f k8s/schema-registry/
    kubectl wait --for=condition=ready pod -l app=schema-registry -n ${NAMESPACE} --timeout=300s || true
    
    echo -e "${YELLOW}Deploying TimescaleDB...${NC}"
    kubectl apply -f k8s/timescaledb/
    kubectl wait --for=condition=ready pod -l app=timescaledb -n ${NAMESPACE} --timeout=300s || true
    
    echo -e "${YELLOW}Deploying Mosquitto...${NC}"
    kubectl apply -f k8s/mosquitto/
    kubectl wait --for=condition=ready pod -l app=mosquitto -n ${NAMESPACE} --timeout=120s || true
    
    echo -e "${YELLOW}Deploying application services...${NC}"
    kubectl apply -f k8s/app-services/
    
    echo -e "${YELLOW}Deploying monitoring stack...${NC}"
    kubectl apply -f k8s/monitoring/
    
    echo -e "${GREEN}✅ Kubernetes resources deployed${NC}"
}

# Setup monitoring
setup_monitoring() {
    echo -e "${YELLOW}Setting up Google Cloud Operations...${NC}"
    
    chmod +x scripts/setup-cloud-monitoring.sh
    ./scripts/setup-cloud-monitoring.sh
    
    echo -e "${GREEN}✅ Monitoring configured${NC}"
}

# Check deployment status
check_status() {
    echo -e "${BLUE}Checking deployment status...${NC}"
    
    echo -e "\n${YELLOW}=== Pods ===${NC}"
    kubectl get pods -n ${NAMESPACE}
    
    echo -e "\n${YELLOW}=== Services ===${NC}"
    kubectl get svc -n ${NAMESPACE}
    
    echo -e "\n${YELLOW}=== PVCs ===${NC}"
    kubectl get pvc -n ${NAMESPACE}
    
    echo -e "\n${YELLOW}=== Ingresses ===${NC}"
    kubectl get ingress -n ${NAMESPACE} 2>/dev/null || echo "No ingresses found"
    
    # Get external IP for Mosquitto
    echo -e "\n${YELLOW}=== MQTT Broker External IP ===${NC}"
    kubectl get svc mosquitto -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    echo ""
}

# Setup port forwarding
setup_port_forwarding() {
    echo -e "${YELLOW}Setting up port forwarding...${NC}"
    
    echo "Starting port forwarding (run in background)..."
    
    # Grafana
    kubectl port-forward -n ${NAMESPACE} svc/grafana 3000:3000 &
    echo "  Grafana: http://localhost:3000"
    
    # Prometheus
    kubectl port-forward -n ${NAMESPACE} svc/prometheus 9090:9090 &
    echo "  Prometheus: http://localhost:9090"
    
    # Application metrics
    kubectl port-forward -n ${NAMESPACE} svc/ruuvitag-adapter 8002:8002 &
    kubectl port-forward -n ${NAMESPACE} svc/kafka-consumer 8001:8001 &
    kubectl port-forward -n ${NAMESPACE} svc/timescaledb-sink 8003:8003 &
    
    echo -e "\n${GREEN}Port forwarding established${NC}"
    echo "Press Ctrl+C to stop port forwarding"
    
    wait
}

# Cleanup deployment
cleanup_deployment() {
    echo -e "${RED}WARNING: This will delete all resources${NC}"
    read -p "Are you sure? (yes/no): " -r
    
    if [[ $REPLY == "yes" ]]; then
        echo -e "${YELLOW}Cleaning up Kubernetes resources...${NC}"
        kubectl delete namespace ${NAMESPACE} --wait=true
        
        echo -e "${YELLOW}Destroying infrastructure...${NC}"
        cd terraform
        terraform destroy -auto-approve
        cd ..
        
        echo -e "${GREEN}✅ Cleanup complete${NC}"
    else
        echo "Cleanup cancelled"
    fi
}

# Full deployment
full_deployment() {
    check_prerequisites
    deploy_infrastructure
    sleep 30  # Wait for cluster to stabilize
    build_and_push_images
    create_secrets
    deploy_kubernetes
    sleep 10
    setup_monitoring
    check_status
    
    echo -e "\n${GREEN}=========================================="
    echo "Full deployment completed successfully!"
    echo "==========================================${NC}"
    
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo "  1. Access Grafana: kubectl port-forward -n ${NAMESPACE} svc/grafana 3000:3000"
    echo "  2. Get MQTT IP: kubectl get svc mosquitto -n ${NAMESPACE}"
    echo "  3. View logs: kubectl logs -n ${NAMESPACE} -l app=<app-name>"
    echo "  4. Access Google Cloud Console:"
    echo "     https://console.cloud.google.com/kubernetes/clusters/details/${ZONE}/${CLUSTER_NAME}?project=${PROJECT_ID}"
}

# Main menu loop
main() {
    check_prerequisites
    
    while true; do
        show_menu
        read -p "Select an option (1-9): " choice
        
        case $choice in
            1)
                full_deployment
                ;;
            2)
                deploy_infrastructure
                ;;
            3)
                build_and_push_images
                ;;
            4)
                create_secrets
                deploy_kubernetes
                ;;
            5)
                setup_monitoring
                ;;
            6)
                check_status
                ;;
            7)
                setup_port_forwarding
                ;;
            8)
                cleanup_deployment
                ;;
            9)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main
main