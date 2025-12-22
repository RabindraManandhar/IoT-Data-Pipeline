# #!/bin/bash
# # Setup Google Cloud Operations (Monitoring & Logging) for GKE

# set -e

# # Colors
# RED='\033[0;31m'
# GREEN='\033[0;32m'
# YELLOW='\033[1;33m'
# NC='\033[0m'

# # Configuration
# PROJECT_ID="${GCP_PROJECT_ID:-prj-mtp-aiot-dip}"
# CLUSTER_NAME="${GKE_CLUSTER_NAME:-iot-pipeline-cluster}"
# ZONE="${GCP_ZONE:-europe-north1-a}"
# NAMESPACE="iot-pipeline"

# echo -e "${GREEN}=========================================="
# echo "Setting up Google Cloud Operations"
# echo "==========================================${NC}"

# # Function to check if gcloud is configured
# check_gcloud() {
#     if ! gcloud config get-value project &> /dev/null; then
#         echo -e "${RED}gcloud is not configured${NC}"
#         exit 1
#     fi
#     echo -e "${GREEN}✅ gcloud is configured${NC}"
# }

# # Create monitoring dashboard
# create_dashboard() {
#     echo -e "${YELLOW}Creating IoT Pipeline monitoring dashboard...${NC}"
    
#     cat > /tmp/iot-dashboard.yaml <<EOF
# displayName: "IoT Data Pipeline (Full PromQL)"
# mosaicLayout:
#   columns: 12
#   tiles:
#     # 1. Kafka Message Rate
#     - width: 6
#       height: 4
#       widget:
#         title: "Kafka Message Rate (msgs/sec)"
#         xyChart:
#           dataSets:
#             - timeSeriesQuery:
#                 prometheusQuery: 'rate(iot_messages_received_total{namespace="${NAMESPACE}"}[5m])'
    
#     # 2. Processing Duration (p95)
#     - xPos: 6
#       width: 6
#       height: 4
#       widget:
#         title: "Processing Duration p95"
#         xyChart:
#           dataSets:
#             - timeSeriesQuery:
#                 prometheusQuery: 'histogram_quantile(0.95, sum(rate(iot_processing_duration_seconds_bucket{namespace="${NAMESPACE}"}[5m])) by (le))'
    
#     # 3. Kafka Consumer Lag
#     - yPos: 4
#       width: 6
#       height: 4
#       widget:
#         title: "Kafka Consumer Lag"
#         xyChart:
#           dataSets:
#             - timeSeriesQuery:
#                 prometheusQuery: 'kafka_consumergroup_lag{namespace="${NAMESPACE}"}'
    
#     # 4. Pod CPU Usage
#     - xPos: 6
#       yPos: 4
#       width: 6
#       height: 4
#       widget:
#         title: "Pod CPU Usage (cores)"
#         xyChart:
#           dataSets:
#             - timeSeriesQuery:
#                 prometheusQuery: 'sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="${NAMESPACE}", container!="POD"}[5m]))'
    
#     # 5. Pod Memory
#     - yPos: 8
#       width: 6
#       height: 4
#       widget:
#         title: "Pod Memory Usage (bytes)"
#         xyChart:
#           dataSets:
#             - timeSeriesQuery:
#                 prometheusQuery: 'sum by (pod) (container_memory_usage_bytes{namespace="${NAMESPACE}", container!="POD"})'
    
#     # 6. Error Rate
#     - xPos: 6
#       yPos: 8
#       width: 6
#       height: 4
#       widget:
#         title: "Error Rate (errors/sec)"
#         xyChart:
#           dataSets:
#             - timeSeriesQuery:
#                 prometheusQuery: 'rate(iot_messages_failed_total{namespace="${NAMESPACE}"}[5m])'
# EOF
    
#     gcloud monitoring dashboards create --config-from-file=/tmp/iot-dashboard.yaml \
#         --project=${PROJECT_ID} || echo "Dashboard already exists or update failed!"
    
#     rm /tmp/iot-dashboard.yaml
    
#     echo -e "${GREEN}✅ Dashboard created${NC}"
# }

# # Create alerting policies
# create_alerts() {
#     echo -e "${YELLOW}Creating alerting policies...${NC}"
    
#     # High error rate alert
#     ###############################################
#     # 1. High Error Rate (Prometheus counter)
#     ###############################################
#     gcloud alpha monitoring policies create \
#         --notification-channels="" \
#         --display-name="IoT Pipeline - High Error Rate" \
#         --condition-display-name="Error rate > 10/min" \
#         --condition-threshold-value=10 \
#         --condition-threshold-duration=300s \
#         --condition-expression='
#           fetch k8s_container
#           | metric "prometheus.googleapis.com/iot_messages_failed_total/counter"
#           | filter resource.namespace_name == "${NAMESPACE}"
#           | group_by 5m, [value_iot_messages_failed_total_aggregate: aggregate(value.iot_messages_failed_total)]
#           | every 1m
#           | condition val() > 10
#         ' \
#         --project=${PROJECT_ID} 2>/dev/null || echo "Error-rate alert may already exist"
    
#     ###############################################
#     # 2. Kafka Consumer Lag Alert (Prometheus gauge)
#     ###############################################
#     gcloud alpha monitoring policies create \
#         --notification-channels="" \
#         --display-name="IoT Pipeline - High Kafka Consumer Lag" \
#         --condition-display-name="Kafka consumer lag > 1000" \
#         --condition-threshold-value=1000 \
#         --condition-threshold-duration=300s \
#         --condition-expression='
#           fetch prometheus_target
#           | metric "prometheus.googleapis.com/kafka_consumer_lag/gauge"
#           | group_by 1m, [ lag_avg: mean(value.kafka_consumer_lag) ]
#           | condition lag_avg > 1000
#         ' \
#         --project=${PROJECT_ID} 2>/dev/null || echo "Kafka lag alert may already exist"

#     ###############################################
#     # 3. Pod Restart Rate (GKE built-in metric)
#     ###############################################
#     gcloud alpha monitoring policies create \
#         --notification-channels="" \
#         --display-name="IoT Pipeline - Pod Restart Rate High" \
#         --condition-display-name="More than 3 pod restarts in 5 min" \
#         --condition-threshold-value=3 \
#         --condition-threshold-duration=0s \
#         --condition-expression='
#           fetch k8s_container
#           | metric "kubernetes.io/container/restart_count"
#           | filter resource.namespace_name == "${NAMESPACE}"
#           | group_by 5m, [ restarts: delta(value.restart_count) ]
#           | condition restarts > 3
#         ' \
#         --project=${PROJECT_ID} 2>/dev/null || echo "Pod restart alert may already exist"

#     # Kafka Broker down alert (Pod readiness)
#     gcloud alpha monitoring policies create \
#         --notification-channels="" \
#         --display-name="IoT Pipeline - Kafka Broker Down" \
#         --condition-display-name="Kafka broker unavailable" \
#         --condition-threshold-value=1 \
#         --condition-threshold-duration=60s \
#         --condition-expression='
#           fetch k8s_pod
#           | filter resource.namespace_name == "${NAMESPACE}"
#           | filter resource.pod_name =~ "kafka-.*"
#           | metric "kubernetes.io/pod/status/ready"
#           | group_by 1m, [value_status_ready_mean: mean(value.status_ready)]
#           | every 1m
#           | condition val() < 1
#         ' \
#         --project=${PROJECT_ID} 2>/dev/null || echo "Alert may already exist"
    
#     echo -e "${GREEN}✅ Alert policies created${NC}"
# }

# # Setup log-based metrics
# create_log_metrics() {
#     echo -e "${YELLOW}Creating log-based metrics...${NC}"
    
#     # Application errors metric
#     gcloud logging metrics create iot_application_errors \
#         --description="Count of application errors in IoT pipeline" \
#         --log-filter='
#           resource.type="k8s_container"
#           resource.labels.namespace_name="${NAMESPACE}"
#           severity="ERROR"
#         ' \
#         --project=${PROJECT_ID} 2>/dev/null || echo "Metric already exists"

#     # Metric for anomaly detections
#     gcloud logging metrics create iot_anomalies_detected \
#         --description="Count of anomaly detections" \
#         --log-filter='
#             resource.type="k8s_container"
#             resource.labels.namespace_name="'${NAMESPACE}'"
#             textPayload=~"ANOMALY"
#         ' \
#         --project=${PROJECT_ID} || echo "Metric already exists"
    
#     # MQTT connection failures
#     gcloud logging metrics create iot_mqtt_connection_failures \
#         --description="MQTT broker connection failures" \
#         --log-filter='
#           resource.type="k8s_container"
#           resource.labels.namespace_name="${NAMESPACE}"
#           textPayload=~"MQTT.*connection.*failed"
#         ' \
#         --project=${PROJECT_ID} 2>/dev/null || echo "Metric already exists"
    
#     echo -e "${GREEN}✅ Log-based metrics created${NC}"
# }

# # Apply PodMonitoring resources for Managed Prometheus
# apply_pod_monitoring() {
#     echo -e "${YELLOW}Applying PodMonitoring resources...${NC}"
    
#     cat <<EOF | kubectl apply -f -
# apiVersion: monitoring.googleapis.com/v1
# kind: PodMonitoring
# metadata:
#   name: ruuvitag-adapter-monitoring
#   namespace: ${NAMESPACE}
# spec:
#   selector:
#     matchLabels:
#       app: ruuvitag-adapter
#   endpoints:
#   - port: metrics
#     interval: 30s
# ---
# apiVersion: monitoring.googleapis.com/v1
# kind: PodMonitoring
# metadata:
#   name: kafka-consumer-monitoring
#   namespace: ${NAMESPACE}
# spec:
#   selector:
#     matchLabels:
#       app: kafka-consumer
#   endpoints:
#   - port: metrics
#     interval: 30s
# ---
# apiVersion: monitoring.googleapis.com/v1
# kind: PodMonitoring
# metadata:
#   name: timescaledb-sink-monitoring
#   namespace: ${NAMESPACE}
# spec:
#   selector:
#     matchLabels:
#       app: timescaledb-sink
#   endpoints:
#   - port: metrics
#     interval: 30s
# ---
# apiVersion: monitoring.googleapis.com/v1
# kind: PodMonitoring
# metadata:
#   name: kafka-monitoring
#   namespace: ${NAMESPACE}
# spec:
#   selector:
#     matchLabels:
#       app: kafka
#   endpoints:
#   - port: metrics
#     interval: 30s
# EOF
    
#     echo -e "${GREEN}✅ PodMonitoring resources applied${NC}"
# }

# # Create notification channels
# setup_notifications() {
#     echo -e "${YELLOW}Setting up notification channels...${NC}"
    
#     echo -e "${YELLOW}To complete notification setup:${NC}"
#     echo "  1. Go to: https://console.cloud.google.com/monitoring/alerting/notifications?project=${PROJECT_ID}"
#     echo "  2. Create notification channels (email, SMS, Slack, etc.)"
#     echo "  3. Update alerting policies to use these channels"
# }

# # Main execution
# main() {
#     check_gcloud
#     create_dashboard
#     create_alerts
#     create_log_metrics
#     apply_pod_monitoring
#     setup_notifications
    
#     echo -e "\n${GREEN}=========================================="
#     echo "Google Cloud Operations setup complete!"
#     echo "==========================================${NC}"
    
#     echo -e "\n${YELLOW}Access your monitoring:${NC}"
#     echo "  Dashboard: https://console.cloud.google.com/monitoring/dashboards?project=${PROJECT_ID}"
#     echo "  Logs: https://console.cloud.google.com/logs/query?project=${PROJECT_ID}"
#     echo "  Metrics: https://console.cloud.google.com/monitoring/metrics-explorer?project=${PROJECT_ID}"
#     echo "  Alerts: https://console.cloud.google.com/monitoring/alerting?project=${PROJECT_ID}"
# }

# main