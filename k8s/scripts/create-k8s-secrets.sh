#!/bin/bash
# Create Kubernetes secrets from Google Secret Manager
# This script creates secrets in the iot-pipeline namespace using values from Secret Manager

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_ID="${GCP_PROJECT_ID:-prj-mtp-aiot-dip}"
NAMESPACE="iot-pipeline"
SECRET_NAME="iot-pipeline-secrets"

echo -e "${GREEN}=========================================="
echo "Creating Kubernetes secrets from Google Secret Manager..."
echo "==========================================${NC}"

# Check if kubectl is configured
check_kubectl() {
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}kubectl is not configured or cluster is not accessible${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ kubectl is configured${NC}"
}

# Check if namespace exists
check_namespace() {
    if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
        echo -e "${YELLOW}Namespace ${NAMESPACE} doesn't exist. Creating...${NC}"
        kubectl create namespace ${NAMESPACE}
    fi
    echo -e "${GREEN}✅ Namespace ${NAMESPACE} ready${NC}"
}

# Get secret from Google Secret Manager
get_secret() {
    local secret_name=$1
    gcloud secrets versions access latest --secret=${secret_name} --project=${PROJECT_ID}
}

# Create Kubernetes secret
create_k8s_secret() {
    echo -e "${YELLOW}Fetching secrets from Google Secret Manager...${NC}"
    
    # Fetch secrets
    POSTGRES_PASSWORD=$(get_secret "postgres-password")
    KAFKA_CLUSTER_ID=$(get_secret "kafka-cluster-id")
    GRAFANA_PASSWORD=$(get_secret "grafana-password")
    
    echo -e "${YELLOW}Creating Kubernetes secret...${NC}"
    
    # Delete existing secret if it exists
    kubectl delete secret ${SECRET_NAME} -n ${NAMESPACE} --ignore-not-found=true
    
    # Create secret
    kubectl create secret generic ${SECRET_NAME} \
        -n ${NAMESPACE} \
        --from-literal=KAFKA_BOOTSTRAP_SERVERS='kafka-0.kafka-headless.${NAMESPACE}.svc.cluster.local:9092,kafka-1.kafka-headless.${NAMESPACE}.svc.cluster.local:9092,kafka-2.kafka-headless.${NAMESPACE}.svc.cluster.local:9092' \
        --from-literal=KAFKA_TOPIC_NAME='iot-sensor-data' \
        --from-literal=SCHEMA_REGISTRY_URL='http://schema-registry.${NAMESPACE}.svc.cluster.local:8081' \
        --from-literal=POSTGRES_HOST='timescaledb.${NAMESPACE}.svc.cluster.local' \
        --from-literal=POSTGRES_PORT='5432' \
        --from-literal=POSTGRES_DB='iot_data' \
        --from-literal=POSTGRES_USER='iot_user' \
        --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
        --from-literal=CLUSTER_ID="${KAFKA_CLUSTER_ID}" \
        --from-literal=GRAFANA_USER='admin' \
        --from-literal=GRAFANA_PASSWORD="${GRAFANA_PASSWORD}" \
        --from-literal=DATA_SOURCE_NAME="postgresql://iot_user:${POSTGRES_PASSWORD}@timescaledb.${NAMESPACE}.svc.cluster.local:5432/iot_data?sslmode=disable"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Kubernetes secret created successfully${NC}"
    else
        echo -e "${RED}❌ Failed to create Kubernetes secret${NC}"
        exit 1
    fi
}

# Main execution
main() {
    check_kubectl
    check_namespace
    create_k8s_secret
    
    echo -e "\n${GREEN}=========================================="
    echo "Secrets created successfully!"
    echo "==========================================${NC}"
}

main


