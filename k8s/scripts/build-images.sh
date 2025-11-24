#!/bin/bash
# Build and push Docker images to Google Artifact Registry
# This script builds all IoT pipeline images and pushes them to GCP Artifact Registry

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-prj-mtp-aiot-dip}"
REGION="${GCP_REGION:-europe-north1}"
REPOSITORY="${ARTIFACT_REGISTRY_REPOSITORY:-iot-pipeline}"
IMAGE_TAG="${IMAGE_TAG:-v1.0.0}"

# Construct Artifact Registry URL
REGISTRY_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}"

echo -e "${GREEN}=========================================="
echo "Build and Push Docker Images to Artifact Registry"
echo "==========================================${NC}"

# Function to check if gcloud is installed
check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        echo -e "${RED}gcloud CLI not found. Please install it first.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ gcloud CLI is available${NC}"
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    echo -e "${YELLOW}Checking gcloud authentication...${NC}"

    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        echo -e "${RED}Not authenticated with gcloud${NC}"
        echo "Please run: gcloud auth login"
        exit 1
    fi

    echo -e "${GREEN}✅ Authenticated with gcloud${NC}"
}

# Function to configure Docker for Artifact Registry
configure_docker() {
    echo -e "${YELLOW}Configuring Docker for Artifact Registry...${NC}"

    gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

    echo -e "${GREEN}✅ Docker configured${NC}"
}

# Function to verify Artifact Registry repository exists
verify_repository() {
    echo -e "${YELLOW}Verifying Artifact Registry repository...${NC}"
    
    if ! gcloud artifacts repositories describe ${REPOSITORY} \
        --location=${REGION} \
        --project=${PROJECT_ID} &>/dev/null; then

        echo -e "${RED}Repository ${REPOSITORY} does not exist${NC}"
        echo "Creating repository..."

        gcloud artifacts repositories create ${REPOSITORY} \
            --repository-format=docker \
            --location=${REGION} \
            --description="Docker repository for IoT Pipeline images" \
            --project=${PROJECT_ID}
            
        echo -e "${GREEN}✅ Repository created${NC}"
    else
        echo -e "${GREEN}✅ Repository exists${NC}"
    fi
}

# Function to build and push a Docker image
build_and_push_images() {
    echo -e "${YELLOW}Building and pushing Docker images...${NC}"
    
    # Build RuuviTag Adapter
    docker build -t ${REGISTRY_URL}/ruuvitag-adapter:${IMAGE_TAG} -f docker/Dockerfile.ruuvitag_adapter .
    docker push ${REGISTRY_URL}/ruuvitag-adapter:${IMAGE_TAG}
    echo -e "${GREEN}✅ Built and pushed ruuvitag-adapter${NC}"
    
    # Build Consumer
    docker build -t ${REGISTRY_URL}/kafka-consumer:${IMAGE_TAG} -f docker/Dockerfile.consumer .
    docker push ${REGISTRY_URL}/kafka-consumer:${IMAGE_TAG}
    echo -e "${GREEN}✅ Built and pushed kafka-consumer${NC}"
    
    # Build TimescaleDB Sink
    docker build -t ${REGISTRY_URL}/timescaledb-sink:${IMAGE_TAG} -f docker/Dockerfile.timescaledb_sink .
    docker push ${REGISTRY_URL}/timescaledb-sink:${IMAGE_TAG}
    echo -e "${GREEN}✅ Built and pushed timescaledb-sink${NC}"
}

# Main execution
main() {
    # Pre-flight checks
    check_gcloud
    check_gcloud_auth
    configure_docker
    verify_repository
    build_and_push_images

    echo "Images pushed to:"
    echo " - ${REGISTRY_URL}/ruuvitag-adapter:${IMAGE_TAG}"
    echo " - ${REGISTRY_URL}/kafka-consumer:${IMAGE_TAG}"
    echo " - ${REGISTRY_URL}/timescaledb-sink:${IMAGE_TAG}"
    
    echo "To use these images in Kubernetes, update your manifests with:"
    echo "  image: ${REGISTRY_URL}/<service-name>:${IMAGE_TAG}"
}

# Run main function
main