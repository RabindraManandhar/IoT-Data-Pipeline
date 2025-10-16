#!/bin/bash
# Quick Start Commands for Optimized K8s Deployment

# ==============================================
# STEP 1: Pre-Deployment Checks
# ==============================================

# Check cluster resources
echo "=== Checking Cluster Resources ==="
kubectl describe nodes | grep -A5 "Capacity"
kubectl top nodes

# Verify kubectl and cluster connection
kubectl cluster-info
kubectl get nodes

# ==============================================
# STEP 2: Deploy Everything (Automated)
# ==============================================

# Option A: Use the automated deployment script
chmod +x k8s/scripts/deploy-all.sh
./k8s/scripts/deploy-all.sh

# ==============================================
# STEP 3: Manual Deployment (Alternative)
# ==============================================

# If automated script fails, deploy manually:

# 1. Create namespace
kubectl apply -f k8s/namespace/namespace.yaml

# 2. Create secrets and configs
kubectl create secret generic iot-pipeline-secrets \
  --from-literal=CLUSTER_ID=$(uuidgen) \
  --from-literal=POSTGRES_USER=iot_user \
  --from-literal=POSTGRES_PASSWORD=iot_password \
  --from-literal=GRAFANA_USER=admin \
  --from-literal=GRAFANA_PASSWORD=admin123 \
  -n iot-pipeline

kubectl apply -f k8s/config/

# 3. Create storage
kubectl apply -f k8s/storage/

# 4. Deploy Kafka (wait for ready)
kubectl apply -f k8s/kafka/
kubectl wait --for=condition=ready pod -l app=kafka -n iot-pipeline --timeout=5m

# 5. Deploy Schema Registry
kubectl apply -f k8s/schema-registry/
kubectl wait --for=condition=ready pod -l app=schema-registry -n iot-pipeline --timeout=3m

# 6. Deploy TimescaleDB
kubectl apply -f k8s/timescaledb/
kubectl wait --for=condition=ready pod -l app=timescaledb -n iot-pipeline --timeout=3m

# 7. Deploy Mosquitto
kubectl apply -f k8s/mosquitto/
kubectl wait --for=condition=ready pod -l app=mosquitto -n iot-pipeline --timeout=2m

# 8. Deploy application services
kubectl apply -f k8s/app-services/

# 9. Deploy monitoring
kubectl apply -f k8s/monitoring/prometheus
kubectl apply -f k8s/monitoring/grafana
kubectl apply -f k8s/monitoring/alertmanager
kubectl apply -f k8s/monitoring/exporters

# ==============================================
# STEP 4: Verify Deployment
# ==============================================

# Check all pods
kubectl get pods -n iot-pipeline

# Check services
kubectl get svc -n iot-pipeline

# Check PVCs
kubectl get pvc -n iot-pipeline

# Check resource usage
kubectl top pods -n iot-pipeline
kubectl top nodes

# ==============================================
# STEP 5: Access Services
# ==============================================

# Port forward to access services locally

# Grafana (Dashboard)
kubectl port-forward -n iot-pipeline svc/grafana 3000:3000
# Access: http://localhost:3000 (admin/admin123)

# Prometheus (Metrics)
kubectl port-forward -n iot-pipeline svc/prometheus 9090:9090
# Access: http://localhost:9090

# AlertManager
kubectl port-forward -n iot-pipeline svc/alertmanager 9095:9093
# Access: http://localhost:9095

# ==============================================
# STEP 6: Monitor and Debug
# ==============================================

# Watch pods
kubectl get pods -n iot-pipeline -w

# Check pod logs (replace <pod-name>)
kubectl logs -n iot-pipeline <pod-name> -f

# Check Kafka logs
kubectl logs -n iot-pipeline kafka-0 -c kafka --tail=100

# Check application logs
kubectl logs -n iot-pipeline -l app=ruuvitag-adapter -f
kubectl logs -n iot-pipeline -l app=kafka-consumer -f
kubectl logs -n iot-pipeline -l app=timescaledb-sink -f

# Describe pod for troubleshooting
kubectl describe pod -n iot-pipeline <pod-name>

# Check events
kubectl get events -n iot-pipeline --sort-by='.lastTimestamp' | tail -20

# ==============================================
# STEP 7: Test the Pipeline
# ==============================================

# Exec into Kafka pod
kubectl exec -it kafka-0 -n iot-pipeline -- bash

# Inside Kafka pod, list topics
kafka-topics --bootstrap-server localhost:9092 --list

# Consume messages from topic
kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic iot-sensor-data \
  --from-beginning

# Check TimescaleDB data
kubectl exec -it timescaledb-0 -n iot-pipeline -- \
  psql -U iot_user -d iot_data -c "SELECT COUNT(*) FROM sensor_readings;"

# ==============================================
# STEP 8: Scaling (If Needed)
# ==============================================

# Scale application services
kubectl scale deployment ruuvitag-adapter --replicas=2 -n iot-pipeline
kubectl scale deployment kafka-consumer --replicas=2 -n iot-pipeline

# Check HPA (if configured)
kubectl get hpa -n iot-pipeline

# ==============================================
# STEP 9: Cleanup
# ==============================================

# Delete everything
kubectl delete namespace iot-pipeline

# Or delete specific components
kubectl delete -f k8s/app-services/
kubectl delete -f k8s/monitoring/
kubectl delete -f k8s/kafka/
kubectl delete -f k8s/timescaledb/

# Delete PVCs (warning: deletes data)
kubectl delete pvc --all -n iot-pipeline

# ==============================================
# TROUBLESHOOTING COMMANDS
# ==============================================

# If Kafka pods won't start
kubectl logs kafka-0 -n iot-pipeline -c kafka-init
kubectl logs kafka-0 -n iot-pipeline -c kafka --previous

# Check if storage is formatted
kubectl exec kafka-0 -n iot-pipeline -- cat /var/lib/kafka/data/meta.properties

# Force delete stuck pod
kubectl delete pod <pod-name> -n iot-pipeline --force --grace-period=0

# Check resource constraints
kubectl describe nodes | grep -A10 "Allocated resources"

# Check for pending PVCs
kubectl get pvc -n iot-pipeline

# Restart deployment
kubectl rollout restart deployment <deployment-name> -n iot-pipeline

# Check ConfigMaps
kubectl get configmap -n iot-pipeline
kubectl describe configmap app-config -n iot-pipeline

# Check Secrets
kubectl get secrets -n iot-pipeline
kubectl describe secret iot-pipeline-secrets -n iot-pipeline

# ==============================================
# PERFORMANCE MONITORING
# ==============================================

# Real-time pod metrics
watch kubectl top pods -n iot-pipeline

# Node resource usage
watch kubectl top nodes

# Detailed resource usage
kubectl describe node <node-name> | grep -A 10 "Allocated resources"

# Check Kafka consumer lag
kubectl exec -it kafka-0 -n iot-pipeline -- \
  kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --group iot-data-consumer \
  --describe

# ==============================================
# BACKUP AND RECOVERY
# ==============================================

# Backup TimescaleDB
kubectl exec timescaledb-0 -n iot-pipeline -- \
  pg_dump -U iot_user iot_data > backup.sql

# Restore TimescaleDB
kubectl exec -i timescaledb-0 -n iot-pipeline -- \
  psql -U iot_user iot_data < backup.sql

# Export Kafka data (to file)
kubectl exec -it kafka-0 -n iot-pipeline -- \
  kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic iot-sensor-data \
  --from-beginning \
  --max-messages 1000 > kafka_backup.json

# ==============================================
# HEALTH CHECKS
# ==============================================

# Check all endpoints
kubectl get endpoints -n iot-pipeline

# Test service connectivity
kubectl run -it --rm debug --image=busybox -n iot-pipeline -- sh
# Inside the pod:
# wget -O- http://grafana:3000/api/health
# wget -O- http://prometheus:9090/-/healthy

# Check DNS resolution
kubectl run -it --rm debug --image=busybox -n iot-pipeline -- \
  nslookup kafka-0.kafka-headless.iot-pipeline.svc.cluster.local