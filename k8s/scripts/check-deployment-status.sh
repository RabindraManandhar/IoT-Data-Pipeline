#!/bin/bash
# Check the status of the IoT Data Pipeline deployment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_ID="${GCP_PROJECT_ID:-prj-mtp-aiot-dip}"
ZONE="${GCP_ZONE:-europe-north1-a}"
CLUSTER_NAME="${GKE_CLUSTER_NAME:-iot-pipeline-cluster}"

echo -e "${CYAN}=========================================="
echo "IoT Data Pipeline - Deployment Status"
echo "==========================================${NC}\n"

# Check cluster status
echo -e "${BLUE}=== Cluster Status ===${NC}"
gcloud container clusters describe ${CLUSTER_NAME} \
    --zone=${ZONE} \
    --project=${PROJECT_ID} \
    --format="table(name,status,currentNodeCount,location)"
echo ""

# Check nodes
echo -e "${BLUE}=== Node Status ===${NC}"
kubectl get nodes -o wide
echo ""

# Check namespaces
echo -e "${BLUE}=== Namespaces ===${NC}"
kubectl get namespaces
echo ""

# Check pods by namespace
echo -e "${BLUE}=== Pod Status by Namespace ===${NC}"
for ns in default data monitoring ingress-nginx; do
    echo -e "${YELLOW}Namespace: $ns${NC}"
    kubectl get pods -n $ns -o wide 2>/dev/null || echo "No pods in namespace $ns"
    echo ""
done

# Check services
echo -e "${BLUE}=== Services ===${NC}"
kubectl get services --all-namespaces
echo ""

# Check ingress
echo -e "${BLUE}=== Ingress ===${NC}"
kubectl get ingress --all-namespaces
echo ""

# Check persistent volumes
echo -e "${BLUE}=== Storage ===${NC}"
kubectl get pv
echo ""
kubectl get pvc --all-namespaces
echo ""

# Check deployment readiness
echo -e "${BLUE}=== Deployment Readiness ===${NC}"
kubectl get deployments --all-namespaces
echo ""

# Check statefulsets
echo -e "${BLUE}=== StatefulSets ===${NC}"
kubectl get statefulsets --all-namespaces
echo ""

# Check for issues
echo -e "${BLUE}=== Pod Issues (Not Running) ===${NC}"
kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded
echo ""

# Check recent events
echo -e "${BLUE}=== Recent Events (Last 10) ===${NC}"
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20
echo ""

# Resource usage
echo -e "${BLUE}=== Resource Usage ===${NC}"
echo -e "${YELLOW}Nodes:${NC}"
kubectl top nodes 2>/dev/null || echo "Metrics not available yet"
echo ""
echo -e "${YELLOW}Pods:${NC}"
kubectl top pods --all-namespaces 2>/dev/null || echo "Metrics not available yet"
echo ""

echo -e "${GREEN}Status check completed!${NC}"