# #!/bin/bash
# # Kafka Pod Debugging Script
# # Save as: debug-kafka.sh and run: chmod +x debug-kafka.sh && ./debug-kafka.sh

# NAMESPACE="iot-pipeline"
# POD_NAME="kafka-2"

# echo "=========================================="
# echo "Kafka Pod Debugging - ${POD_NAME}"
# echo "=========================================="

# echo -e "\n1. Pod Status:"
# kubectl get pod ${POD_NAME} -n ${NAMESPACE}

# echo -e "\n2. Pod Events (last 10):"
# kubectl get events -n ${NAMESPACE} --field-selector involvedObject.name=${POD_NAME} \
#   --sort-by='.lastTimestamp' | tail -10

# echo -e "\n3. Init Container Logs:"
# kubectl logs ${POD_NAME} -n ${NAMESPACE} -c kafka-init --tail=50

# echo -e "\n4. Main Container Logs:"
# kubectl logs ${POD_NAME} -n ${NAMESPACE} -c kafka --tail=100

# echo -e "\n5. Previous Container Logs (if restarted):"
# kubectl logs ${POD_NAME} -n ${NAMESPACE} -c kafka --previous 2>/dev/null || echo "No previous logs"

# echo -e "\n6. Pod Description (Conditions):"
# kubectl describe pod ${POD_NAME} -n ${NAMESPACE} | grep -A 20 "Conditions:"

# echo -e "\n7. PVC Status:"
# kubectl get pvc -n ${NAMESPACE} | grep kafka

# echo -e "\n8. Storage Check (if pod is running):"
# kubectl exec ${POD_NAME} -n ${NAMESPACE} -c kafka -- df -h /var/lib/kafka/data 2>/dev/null || echo "Cannot access storage"

# echo -e "\n9. Meta Properties Check:"
# kubectl exec ${POD_NAME} -n ${NAMESPACE} -c kafka -- cat /var/lib/kafka/data/meta.properties 2>/dev/null || echo "Cannot read meta.properties"

# echo -e "\n10. Resource Usage:"
# kubectl top pod ${POD_NAME} -n ${NAMESPACE} 2>/dev/null || echo "Metrics not available"

# echo -e "\n=========================================="
# echo "Debugging Complete"
# echo "=========================================="