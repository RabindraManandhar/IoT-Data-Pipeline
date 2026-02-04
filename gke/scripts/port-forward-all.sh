#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

NAMESPACE="iot-pipeline"

echo -e "${GREEN}=========================================="

# This command forwards port 1883 from the Mosquitto service in the "${NAMESPACE}" namespace 
# to all network interfaces (0.0.0.0) on your host, making the MQTT broker accessible externally
# at <Host-IP>:1883

echo "Starting port forwarding from the Mosquitto service"
kubectl port-forward -n ${NAMESPACE} --address 0.0.0.0 svc/mosquitto 1883:1883 &
echo "Mosquitto service started at port 18883 ..."


echo "============================================="

echo "Starting port forwarding for all monitoring interfaces..."

# Main monitoring
kubectl port-forward -n ${NAMESPACE} svc/grafana 3000:3000 &
kubectl port-forward -n ${NAMESPACE} svc/prometheus 9090:9090 &
kubectl port-forward -n ${NAMESPACE} svc/mailpit 8025:8025 &
kubectl port-forward -n ${NAMESPACE} svc/alertmanager 9093:9093 &

# Application metrics
kubectl port-forward -n ${NAMESPACE} svc/ruuvitag-adapter 8002:8002 &
kubectl port-forward -n ${NAMESPACE} svc/kafka-consumer 8001:8001 &
kubectl port-forward -n ${NAMESPACE} svc/timescaledb-sink 8003:8003 &

# Infrastructure metrics
kubectl port-forward -n ${NAMESPACE} svc/kafka-jmx-exporter 9101:9101 &
kubectl port-forward -n ${NAMESPACE} svc/postgres-exporter 9187:9187 &
kubectl port-forward -n ${NAMESPACE} svc/mosquitto-exporter 9234:9234 &

echo "============================================="

echo ""
echo "Port forwarding started for all services!"
echo ""
echo "Access the following URLs:"
echo "  Grafana:              http://localhost:3000"
echo "  Prometheus:           http://localhost:9090"
echo "  AlertManager:         http://localhost:9093"
echo "  MailPit:              http://localhost:8025"
echo "  RuuviTag Adapter:     http://localhost:8002/metrics"
echo "  Kafka Consumer:       http://localhost:8001/metrics"
echo "  TimescaleDB Sink:     http://localhost:8003/metrics"
echo "  Kafka JMX:            http://localhost:9101/metrics"
echo "  PostgreSQL Exporter:  http://localhost:9187/metrics"
echo "  Mosquitto Exporter:   http://localhost:9234/metrics"
echo ""
echo "Press Ctrl+C to stop all port forwarding"

# Wait for Ctrl+C
wait