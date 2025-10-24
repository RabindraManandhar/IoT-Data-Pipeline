#!/bin/bash

echo "Starting port forwarding for all monitoring interfaces..."

# Main monitoring
kubectl port-forward -n iot-pipeline svc/grafana 3000:3000 &
kubectl port-forward -n iot-pipeline svc/prometheus 9090:9090 &
kubectl port-forward -n iot-pipeline svc/alertmanager 9093:9093 &

# Application metrics
kubectl port-forward -n iot-pipeline svc/ruuvitag-adapter 8002:8002 &
kubectl port-forward -n iot-pipeline svc/kafka-consumer 8001:8001 &
kubectl port-forward -n iot-pipeline svc/timescaledb-sink 8003:8003 &

# Infrastructure metrics
kubectl port-forward -n iot-pipeline svc/kafka-jmx-exporter 9101:9101 &
kubectl port-forward -n iot-pipeline svc/postgres-exporter 9187:9187 &
kubectl port-forward -n iot-pipeline svc/mosquitto-exporter 9234:9234 &

echo ""
echo "Port forwarding started for all services!"
echo ""
echo "Access the following URLs:"
echo "  Grafana:              http://localhost:3000"
echo "  Prometheus:           http://localhost:9090"
echo "  AlertManager:         http://localhost:9093"
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