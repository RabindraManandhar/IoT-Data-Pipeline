# #!/bin/bash
# # Complete deployment script for IoT Data Pipeline on Kubernetes

# set -e

# # Colors for output
# RED='\033[0;31m'
# GREEN='\033[0;32m'
# YELLOW='\033[1;33m'
# NC='\033[0m' # No Color

# # Configuration
# NAMESPACE="iot-pipeline"
# REGISTRY="rabindramdr" # Change to your container registry
# IMAGE_TAG="v1.0.0"
# MOSQUITTO_SERVICENAME="mosquitto"

# echo -e "${GREEN}Starting Iot Data Pipeline Kuberenetes Deployment${NC}"
# echo -e "${YELLOW}Cluster Resources: 8 CPUs, ~1TB Storage${NC}"

# # Function to check if kubectl is available
# check_kubectl() {
#     if ! command -v kubectl &> /dev/null; then
#         echo -e "${RED}kubectl not found. Please install kubectl.${NC}"
#         exit 1
#     fi
#     echo -e "${GREEN}✅ kubectl is available${NC}"
# }

# # Function to check if cluster is accessible
# check_cluster() {
#     if ! kubectl cluster-info &> /dev/null; then
#         echo -e "${RED}Cannot connect to Kubernetes cluster${NC}"
#         exit 1
#     fi
#     echo -e "${GREEN}✅ Connected to Kubernetes cluster${NC}"
# }

# # Function to check available resources
# check_resources() {
#     echo -e "\n${YELLOW}Checking available cluster resources...${NC}"
    
#     # Get total allocatable resources
#     TOTAL_CPU=$(kubectl get nodes -o json | jq -r '.items[].status.allocatable.cpu' | awk '{s+=$1} END {print s}')
#     TOTAL_MEM=$(kubectl get nodes -o json | jq -r '.items[].status.allocatable.memory' | sed 's/Ki//' | awk '{s+=$1} END {printf "%.0f\n", s/1024/1024}')
    
#     echo "Total Allocatable CPU: ${TOTAL_CPU} cores"
#     echo "Total Allocatable Memory: ${TOTAL_MEM} Gi"
    
#     # Check if we have enough resources
#     REQUIRED_CPU=3
#     REQUIRED_MEM=8
    
#     if (( $(echo "$TOTAL_CPU < $REQUIRED_CPU" | bc -l) )); then
#         echo -e "${RED}⚠️  Warning: Available CPU (${TOTAL_CPU}) is less than recommended (${REQUIRED_CPU})${NC}"
#         read -p "Continue anyway? (y/n) " -n 1 -r
#         echo
#         if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#             exit 1
#         fi
#     fi
# }

# # Function to build and push Docker images
# build_and_push_images() {
#     echo -e "${YELLOW}Building and pushing Docker images...${NC}"
    
#     # Build RuuviTag Adapter
#     docker build -t ${REGISTRY}/ruuvitag-adapter:${IMAGE_TAG} -f docker/Dockerfile.ruuvitag_adapter .
#     docker push ${REGISTRY}/ruuvitag-adapter:${IMAGE_TAG}
#     echo -e "${GREEN}✅ Built and pushed ruuvitag-adapter${NC}"
    
#     # Build Consumer
#     docker build -t ${REGISTRY}/kafka-consumer:${IMAGE_TAG} -f docker/Dockerfile.consumer .
#     docker push ${REGISTRY}/kafka-consumer:${IMAGE_TAG}
#     echo -e "${GREEN}✅ Built and pushed kafka-consumer${NC}"
    
#     # Build TimescaleDB Sink
#     docker build -t ${REGISTRY}/timescaledb-sink:${IMAGE_TAG} -f docker/Dockerfile.timescaledb_sink .
#     docker push ${REGISTRY}/timescaledb-sink:${IMAGE_TAG}
#     echo -e "${GREEN}✅ Built and pushed timescaledb-sink${NC}"
# }

# # Function to create namespace
# create_namespace() {
#     echo -e "${YELLOW}Creating namespace...${NC}"
#     kubectl apply -f k8s/namespace/namespace.yaml
#     echo -e "${GREEN}✅ Namespace created${NC}"
# }

# # Function to create storage
# create_storage() {
#     echo -e "${YELLOW}Creating storage classes and PVCs...${NC}"
#     kubectl apply -f k8s/storage/
#     echo -e "${GREEN}✅ Storage created${NC}"
# }

# # Function to create configs and secrets
# create_configs() {
#     echo -e "${YELLOW}Creating ConfigMaps and Secrets...${NC}"
#     kubectl apply -f k8s/config/
#     echo -e "${GREEN}✅ ConfigMaps and Secrets created${NC}"
# }

# # Function to create RBAC serviceaccount, roles and clusterroles
# create_rbac() {
#     echo -e "${YELLOW}Creating RBAC serviceaccount, roles and clusterroles...${NC}"
#     kubectl apply -f k8s/rbac/
#     echo -e "${GREEN}✅ RBAC serviceaccount, roles and clusterrole created${NC}"
# }

# # Function to deploy Kafka
# deploy_kafka() {
#     echo -e "${YELLOW}Deploying Kafka cluster...${NC}"
#     kubectl apply -f k8s/kafka/

#     # Wait for Kafka to be ready
#     echo "Waiting for Kafka pods to be ready (this may take 2-3 minutes)..."
    
#     if kubectl wait --for=condition=ready pod -l app=kafka \
#         -n ${NAMESPACE} --timeout=600s 2>/dev/null; then
#         echo -e "${GREEN}✅ Kafka cluster deployed${NC}"
#     else
#         echo -e "${RED}❌ Kafka pods failed to become ready${NC}"
#         echo -e "${YELLOW}Debugging information:${NC}"
        
#         # Show pod status
#         echo -e "\nPod status:"
#         kubectl get pods -n ${NAMESPACE} -l app=kafka
        
#         # Show pod logs for kafka
#         echo -e "\Pod logs (kafka-0):"
#         kubectl logs kafka-0 -n ${NAMESPACE} -c kafka --tail=30 2>/dev/null || echo "Not available"

#         # Troubleshooting
#         echo -e "\n${YELLOW}Troubleshooting options:${NC}"
#         echo "1. Check full logs for kafka-init: kubectl logs kafka-0 -n ${NAMESPACE} -c kafka-init"
#         echo "2. Check full logs for pod (kafka-0): kubectl logs kafka-0 -n ${NAMESPACE} -c kafka"
#         echo "3. Describe the pod (kafka-0): kubectl describe pod kafka-0 -n ${NAMESPACE}"
#         echo "4. Show recent events: kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | grep kafka | tail -10"
#         echo "5. Watch the rollout: kubectl rollout status statefulset/kafka -n ${NAMESPACE}"
#         echo "6. Get the logs from the previous run: kubectl logs kafka-0 -n ${namespace} -c kafka --previous"
         
#         read -p "Continue deployment anyway? (y/n) " -n 1 -r
#         echo
#         if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#             exit 1
#         fi
#     fi
# }

# # Function to deploy Schema Registry
# deploy_schema_registry() {
#     echo -e "${YELLOW}Deploying Schema Registry...${NC}"
#     kubectl apply -f k8s/schema-registry/
    
#     # Wait for Schema Registry to be ready
#     echo "Waiting for Schema Registry to be ready..."

#     if kubectl wait --for=condition=ready pod -l app=schema-registry \
#         -n ${NAMESPACE} --timeout=600s 2>/dev/null; then
#         echo -e "${GREEN}✅ Schema Registry deployed${NC}"
#     else
#         echo -e "${RED}❌ Schema registry pod failed to become ready${NC}"
#         echo -e "${YELLOW}Debbuging information:${NC}"

#         # Show pod status
#         echo -e "\nPod status:"
#         kubectl get pods -n ${NAMESPACE} -l app=schema-registry

#         # Troubleshooting
#         echo -e "\n${YELLOW}Troubleshooting options:${NC}"
#         echo "1. Check logs of schema-registry pod: kubectl logs <pod_name> -n ${NAMESPACE} -c schema-registry"
#         echo "3. Describe schema-registry pod: kubectl describe pod <pod_name> -n ${NAMESPACE}"
#         echo "4. Show recent events: kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | grep schema-registry | tail -10"
#         echo "5. Get the logs from the previous run: kubectl logs <pod_name> -n ${namespace} -c schema-registry --previous" 
        
#         read -p "Continue deployment anyway? (y/n) " -n 1 -r
#         echo
#         if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#             exit 1
#         fi
#     fi
# }

# # Function to deploy TimescaleDB
# deploy_timescaledb() {
#     echo -e "${YELLOW}Deploying TimescaleDB...${NC}"
#     kubectl apply -f k8s/timescaledb/
    
#     # Wait for TimescaleDB to be ready
#     echo "Waiting for TimescaleDB to be ready..."
#     kubectl wait --for=condition=ready pod -l app=timescaledb \
#         -n ${NAMESPACE} --timeout=300s
#     echo -e "${GREEN}✅ TimescaleDB deployed${NC}"
# }

# # Function to deploy Mosquitto
# deploy_mosquitto() {
#     echo -e "${YELLOW}Deploying Mosquitto MQTT Broker...${NC}"
#     kubectl apply -f k8s/mosquitto/
    
#     # Wait for Mosquitto to be ready
#     echo "Waiting for Mosquitto to be ready..."
#     kubectl wait --for=condition=ready pod -l app=mosquitto \
#         -n ${NAMESPACE} --timeout=120s
#     echo -e "${GREEN}✅ Mosquitto deployed${NC}"
# }

# # Function to deploy application services
# deploy_app_services() {
#     echo -e "${YELLOW}Deploying application services...${NC}"
#     kubectl apply -f k8s/app-services/
    
#     # Wait for application services to be ready
#     echo "Waiting for application services to be ready..."
#     sleep 10

#     # Check each service
#     for app in ruuvitag-adapter kafka-consumer timescaledb-sink; do
#         if kubectl wait --for=condition=ready pod -l app=$app \
#             -n ${NAMESPACE} --timeout=180s 2>/dev/null; then
#             echo -e "${GREEN}✅ $app deployed${NC}"
#         else
#             echo -e "${YELLOW}⚠️  $app not fully ready${NC}"
#         fi
#     done

#     echo -e "${GREEN}✅ Application services deployed${NC}"
# }

# # Function to deploy monitoring
# deploy_monitoring() {
#     echo -e "${YELLOW}Deploying monitoring stack...${NC}"
#     kubectl apply -f k8s/monitoring/prometheus/
#     kubectl apply -f k8s/monitoring/grafana/
#     kubectl apply -f k8s/monitoring/alertmanager/
#     kubectl apply -f k8s/monitoring/exporters/
    
#     # Wait for monitoring services to be ready
#     echo "Waiting for monitoring services to be ready..."
#     sleep 15

#     for app in prometheus grafana; do
#         if kubectl wait --for=condition=ready pod -l app=$app \
#             -n ${NAMESPACE} --timeout=180s 2>/dev/null; then
#             echo -e "${GREEN}✅ $app deployed${NC}"
#         else
#             echo -e "${YELLOW}⚠️  $app not fully ready${NC}"
#         fi
#     done
    
#     echo -e "${GREEN}✅ Monitoring stack deployed${NC}"
# }

# # Function to display status
# display_status() {
#     echo -e "\n${GREEN}Deployment Status:${NC}"
#     kubectl get all -n ${NAMESPACE}
    
#     echo -e "\n${GREEN}PersistentVolumeClaims:${NC}"
#     kubectl get pvc -n ${NAMESPACE}

#     echo -e "\n${YELLOW}Resource Usage:${NC}"
#     kubectl top pods -n ${NAMESPACE} 2>/dev/null || echo "Metrics server not available"

    
#     echo -e "\n${YELLOW}Services and Endpoints:${NC}"
#     kubectl get svc -n ${NAMESPACE}
# }

# # Main deployment flow
# main() {
#     echo "=========================================="
#     echo "IoT Data Pipeline - Kubernetes Deployment"
#     echo "=========================================="
    
#     # Pre-flight checks
#     check_kubectl
#     check_cluster
#     check_resources
    
#     # Option to build images
#     read -p "Build and push Docker images? (y/n) " -n 1 -r
#     echo
#     if [[ $REPLY =~ ^[Yy]$ ]]; then
#         build_and_push_images
#     fi
    
#     # Deploy infrastructure
#     create_namespace
#     create_storage
#     create_configs

#     # Deploy RBAC
#     create_rbac
    
#     # Deploy services in order
#     deploy_kafka
#     sleep 10  # Give Kafka time to stabilize
    
#     deploy_schema_registry
#     deploy_timescaledb
#     deploy_mosquitto
    
#     sleep 5  # Brief pause before deploying apps
    
#     deploy_app_services
#     deploy_monitoring
    
#     # # Optional: Create ingress
#     # read -p "Create ingress resources? (y/n) " -n 1 -r
#     # echo
#     # if [[ $REPLY =~ ^[Yy]$ ]]; then
#     #     create_ingress
#     # fi
    
#     # Display final status
#     display_status
    
#     echo -e "\n${GREEN}=========================================="
#     echo "Deployment Complete!"
#     echo "==========================================${NC}"

#     echo -e "\nAccess Services:"
#     echo "  Grafana: kubectl port-forward -n ${NAMESPACE} svc/grafana 3000:3000"
#     echo "  Prometheus: kubectl port-forward -n ${NAMESPACE} svc/prometheus 9090:9090"
#     echo "  AlertManager: kubectl port-forward -n ${NAMESPACE} svc/alertmanager 9093:9093"
    
#     echo -e "\nMonitor pods:"
#     echo "  kubectl get pods -n ${NAMESPACE} -w"

#     echo -e "\nView logs:"
#     echo "  kubectl logs -n ${NAMESPACE} -l app=<app-name> -f"
    
#     echo -e "\n${YELLOW}Note: This is an optimized deployment for an 8-CPU cluster.${NC}"
#     echo -e "${YELLOW}For production, consider scaling to 16-32 CPUs.${NC}"
# }

# # Run main function
# main
