#!/bin/bash
# Check status of all components

NAMESPACE="iot-pipeline"

echo "=========================================="
echo "IoT Data Pipeline - Status Check"
echo "=========================================="

echo -e "\n📦 Pods:"
kubectl get pods -n ${NAMESPACE}

echo -e "\n🔧 Services:"
kubectl get svc -n ${NAMESPACE}

echo -e "\n💾 PersistentVolumeClaims:"
kubectl get pvc -n ${NAMESPACE}

echo -e "\n📊 Resource Usage:"
kubectl top pods -n ${NAMESPACE} 2>/dev/null || echo "Metrics server not available"

echo -e "\n🔍 Recent Events:"
kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | tail -n 20