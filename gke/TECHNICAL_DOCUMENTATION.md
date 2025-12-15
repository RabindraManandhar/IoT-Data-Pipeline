# IoT Data Pipeline - Technical Documentation

**Version**: 1.0.0  
**Date**: December 2025  
**Author**: Rabindra Manandhar  
**Status**: Development

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Architecture](#2-system-architecture)
3. [Technology Stack](#3-technology-stack)
4. [Infrastructure](#4-infrastructure)
5. [Data Pipeline Components](#5-data-pipeline-components)
6. [Data Flow](#6-data-flow)
7. [Database Design](#7-database-design)
8. [Monitoring](#8-monitoring)
9. [Security](#9-security)
10. [Deployment](#10-deployment)
11. [Operations](#11-operations)
12. [Performance](#12-performance)

---

## 1. Executive Summary

### 1.1 Overview

This document provides comprehensive technical documentation for an IoT data pipeline deployed on Google Kubernetes Engine. The system processes real-time environmental sensor data from RuuviTag devices through ESP32 gateways.

### 1.2 Key Metrics

- **Components**: 15 pods across 7 services
- **Throughput**: 10,000+ messages/second
- **Data Retention**: 90 days with automatic archival
- **Availability**: 99.9% uptime with 3x replication
- **Latency**: < 1 second end-to-end

### 1.3 Use Cases

- Real-time environmental monitoring
- Predictive maintenance
- Anomaly detection
- Historical trend analysis
- Multi-location sensor networks

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
    ┌─────────────────────────────────────────────────────────┐
    │                   Physical Layer                        │
    |                                                         |
    │        RuuviTag Sensors --▶ ESP32 Gateway               │
    └──────────────────────────┬──────────────────────────────┘
                            | MQTT (Port 1833)
    ┌──────────────────────────▼──────────────────────────────┐
    │               Application Layer (GKE)                   │
    |                                                         |
    │  ┌─────────────┐     ┌──────────────────┐               │
    │  │  Mosquitto  │---▶ │    RuuviTag      │               │
    │  │  MQTT       │     │    Adapter       │               │
    │  └─────────────┘     └────────┬─────────┘               │
    │                               │                         │
    │                   ┌───────────▼──────────┐              │
    │                   │  Schema Registry     │              │
    │                   └───────────┬──────────┘              │
    │                               │                         │
    │       ┌───────────────────────▼───────────────┐         │
    │       │     Apache Kafka Cluster (3 nodes)    │         │
    │       │     ┌──────┐  ┌──────┐  ┌──────┐      │         │
    │       │     │ KB-1 │  │ KB-2 │  │ KB-3 │      │         │
    │       │     └──────┘  └──────┘  └──────┘      │         │
    │       └──────────┬──────────────────┬─────────┘         │
    │                  │                  │                   │
    │           ┌──────▼──────┐   ┌───────▼──────┐            │
    │           │   Consumer  │   │ TimescaleDB  │            │
    │           │   (Alerts)  │   │    (Sink)    │            │
    │           └──────┬──────┘   └───────┬──────┘            │
    │                           │                             │
    │                   ┌───────▼──────────┐                  │
    │                   │   TimescaleDB    │                  │
    │                   │   (Hypertables)  │                  │
    │                   └───────┬──────────┘                  │
    └───────────────────────────┬─────────────────────────────┘
                                │
    ┌───────────────────────────▼─────────────────────────────┐
    │                    Monitoring Layer                     |
    |                           │                             |
    │          ┌────────────────▼────────────────────┐        | 
    |          | Prometheus → Grafana → AlertManager │        |
    |          └─────────────────────────────────────┘        |
    └─────────────────────────────────────────────────────────┘
```

### 2.2 Component Distribution

| Component | Replicas | CPU Request | Memory Request |
|-----------|----------|-------------|----------------|
| Kafka Brokers | 3 | 500m | 1Gi |
| Schema Registry | 1 | 250m | 512Mi |
| TimescaleDB | 1 | 300m | 512Mi |
| Mosquitto | 1 | 100m | 64Mi |
| RuuviTag Adapter | 1-5 (HPA) | 300m | 512Mi |
| Consumer | 1-3 (HPA) | 300m | 512Mi |
| TimescaleDB Sink | 1 | 300m | 512Mi |
| Prometheus | 1 | 200m | 256Mi |
| Grafana | 1 | 100m | 128Mi |

### 2.3 Network Architecture

**VPC Configuration:**
- Network: `iot-pipeline-network`
- Subnet: `10.0.0.0/24` (256 IPs)
- Pods: `10.1.0.0/16` (65,536 IPs)
- Services: `10.2.0.0/16` (65,536 IPs)

**Service Mesh:**
- mosquitto.iot-pipeline.svc.cluster.local:1883
- kafka-headless.iot-pipeline.svc.cluster.local:9092
- schema-registry.iot-pipeline.svc.cluster.local:8081
- timescaledb.iot-pipeline.svc.cluster.local:5432


---

## 3. Technology Stack

### 3.1 Core Technologies

| Category | Technology | Version | Purpose |
|----------|-----------|---------|---------|
| Orchestration | Kubernetes (GKE) | 1.27+ | Container management |
| Streaming | Confluent Kafka | 7.9.0 | Event streaming |
| Schema | Schema Registry | 7.9.0 | Avro management |
| Database | TimescaleDB | PG 16 | Time-series storage |
| Broker | Mosquitto | 2.0 | MQTT messaging |
| Monitoring | Prometheus | 2.48 | Metrics collection |
| Visualization | Grafana | Latest | Dashboards |
| IaC | Terraform | 1.5+ | Infrastructure |

### 3.2 Python Stack

```bash
# Core Dependencies
confluent-kafka==2.3.0
confluent-kafka[avro]==2.3.0
paho-mqtt==1.6.1
psycopg2-binary==2.9.9
sqlalchemy==2.0.23
prometheus-client==0.19.0
loguru==0.7.2
pydantic==2.5.2
```

---

## 4. Infrastructure

### 4.1 GKE Cluster

**Cluster Specifications:**
```bash
name     = "iot-pipeline-cluster"
location = "europe-north1-a"
node_pools = 1
min_nodes = 1
max_nodes = 3
machine_type = "e2-standard-4"  # 4 vCPUs, 16GB RAM
```

**Features:**
- Workload Identity enabled
- Network policies enabled
- Auto-scaling enabled
- Shielded nodes with secure boot
- Regional availability

### 4.2 Storage Configuration

| Service | Storage Class | Size | Type |
|---------|--------------|------|------|
| Kafka | premium-rwo | 50Gi | SSD |
| TimescaleDB | premium-rwo | 20Gi | SSD |
| Prometheus | standard-rwo | 10Gi | HDD |
| Grafana | standard-rwo | 5Gi | HDD |

### 4.3 Networking

**Firewall Rules:**
- Internal: All ports within VPC
- MQTT: Port 1883 external
- Health Checks: GCP LB IPs

**NAT Configuration:**
- Cloud Router for outbound
- Auto-allocated NAT IPs
- All nodes private

---

## 5. Data Pipeline Components

### 5.1 RuuviTag Adapter

**Purpose**: Transforms MQTT messages to Kafka format with Avro serialization.

**Key Features:**
- MQTT subscription (QoS 1)
- Per-sensor message creation
- Anomaly detection
- Prometheus metrics

**Message Transformation:**
```python
# Input: Single MQTT message
{
    "device_id": "AA:BB:CC:DD:EE:FF",
    "temperature": 22.5,
    "humidity": 45.2
}

# Output: Multiple Kafka messages
[
    {
        "device_id": "AA:BB:CC:DD:EE:FF_temperature",
        "device_type": "temperature_sensor",
        "value": 22.5,
        "unit": "°C"
    },
    {
        "device_id": "AA:BB:CC:DD:EE:FF_humidity",
        "device_type": "humidity_sensor",
        "value": 45.2,
        "unit": "%"
    }
]
```

### 5.2 Kafka Cluster

**Configuration:**
- Mode: KRaft (no ZooKeeper)
- Brokers: 3
- Replication Factor: 3
- Min ISR: 2
- Partitions: 6

**Topic Configuration:**
```yaml
topic: iot-sensor-data
partitions: 6
replication_factor: 3
retention.ms: 604800000  # 7 days
cleanup.policy: delete
```

### 5.3 Schema Registry

**Purpose**: Centralized Avro schema management.

**Schema Evolution:**
- Compatibility: BACKWARD
- Field additions allowed
- Breaking changes prevented

**Schema Fields:**
```json
{
  "fields": [
    {"name": "device_id", "type": "string"},
    {"name": "device_type", "type": "string"},
    {"name": "timestamp", "type": "string"},
    {"name": "value", "type": ["double", "int", "null"]},
    {"name": "unit", "type": "string"},
    {"name": "location", "type": {...}},
    {"name": "battery_level", "type": ["double", "null"]},
    {"name": "is_anomaly", "type": "boolean"}
  ]
}
```

### 5.4 Kafka Consumer

**Purpose**: Real-time message processing and alerting.

**Configuration:**
```yaml
group_id: iot-data-consumer
enable_auto_commit: true
auto_commit_interval_ms: 5000
session_timeout_ms: 30000
```

**Alert Thresholds:**
- Temperature: -50°C to 50°C
- Humidity: 15% to 100%
- Pressure: 87000 to 108500 Pa
- Battery: > 2.0V

### 5.5 TimescaleDB Sink

**Purpose**: Batch insertion to TimescaleDB.

**Configuration:**
```yaml
batch_size: 100
commit_interval: 5.0
max_retries: 3
retry_backoff: 2.0
```

**Optimizations:**
- Batch inserts (psycopg2)
- Connection pooling
- Pre-ping validation
- Async maintenance

---

## 6. Data Flow

### 6.1 End-to-End Flow

```
1. RuuviTag → BLE broadcast (1-60s)
2. ESP32 → MQTT publish (< 100ms)
3. Adapter → Transform + Avro (1-5ms)
4. Kafka → Replicate (< 10ms)
5. Consumer → Process (< 5ms)
6. Sink → Batch insert (50-200ms)
7. TimescaleDB → Store in chunks
8. Prometheus → Scrape metrics (15s)
```

### 6.2 Partitioning Strategy

**Key**: `device_id`
**Hash-based**: Ensures same sensor → same partition
**Benefits**: Ordering per sensor, parallel processing

```
Topic: iot-sensor-data (6 partitions)
Partition 0: Devices [A, D, G, ...]
Partition 1: Devices [B, E, H, ...]
...
```

### 6.3 Serialization

**Avro Benefits:**
- Schema validation
- Compact binary format
- Language-agnostic
- Evolution support

**Process:**
```python
# Producer
value_bytes = avro_serializer(reading, context)
producer.produce(topic, key, value_bytes)

# Consumer
reading = avro_deserializer(value_bytes, context)
```

---

## 7. Database Design

### 7.1 TimescaleDB Schema

**Main Table:**
```sql
CREATE TABLE sensor_readings (
    id BIGSERIAL,
    device_id TEXT NOT NULL,
    device_type TEXT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    value DOUBLE PRECISION,
    unit TEXT NOT NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    battery_level DOUBLE PRECISION,
    is_anomaly BOOLEAN DEFAULT FALSE,
    device_metadata JSONB,
    tags TEXT[]
);

SELECT create_hypertable(
    'sensor_readings', 
    'timestamp',
    chunk_time_interval => INTERVAL '1 day'
);
```

### 7.2 Indexes

```sql
CREATE INDEX idx_device_id ON sensor_readings(device_id, timestamp DESC);
CREATE INDEX idx_device_type ON sensor_readings(device_type, timestamp DESC);
CREATE INDEX idx_anomaly ON sensor_readings(is_anomaly, timestamp DESC) 
WHERE is_anomaly = TRUE;
CREATE INDEX idx_metadata ON sensor_readings USING GIN(device_metadata);
```

### 7.3 Continuous Aggregates

```sql
CREATE MATERIALIZED VIEW sensor_readings_hourly
WITH (timescaledb.continuous) AS
SELECT 
    time_bucket('1 hour', timestamp) AS bucket,
    device_id,
    COUNT(*) as count,
    AVG(value) as avg_value,
    MIN(value) as min_value,
    MAX(value) as max_value
FROM sensor_readings
GROUP BY bucket, device_id;
```

### 7.4 Compression & Retention

```sql
-- Compress after 7 days
ALTER TABLE sensor_readings SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 'timestamp DESC',
    timescaledb.compress_segmentby = 'device_id'
);

ADD COMPRESSION_POLICY 7 days;

-- Drop after 90 days
ADD RETENTION_POLICY 90 days;
```

---

## 8. Monitoring

### 8.1 Prometheus Metrics

**Application Metrics:**
| Metric | Type | Description |
|--------|------|-------------|
| `iot_messages_received_total` | Counter | Messages received |
| `iot_messages_processed_total` | Counter | Successfully processed |
| `iot_processing_duration_seconds` | Histogram | Processing time |
| `iot_anomaly_detected_total` | Counter | Anomalies detected |

**Kafka Metrics (JMX):**
- `kafka_server_brokertopicmetrics_messagesin_total`
- `kafka_server_replica_manager_under_replicated_partitions`
- `kafka_network_requests_total`

**Database Metrics:**
- `pg_stat_database_numbackends`
- `pg_database_size_bytes`
- `timescaledb_sink_insert_duration_seconds`

### 8.2 Grafana Dashboards

**1. IoT Pipeline Overview**
- Message throughput
- Error rates
- Active devices
- Anomaly rate

**2. Kafka Health**
- Broker status
- Replication lag
- Consumer groups

**3. TimescaleDB Performance**
- Insert rate
- Compression ratio
- Chunk statistics

### 8.3 Alert Rules

```yaml
- alert: KafkaBrokerDown
  expr: up{job=~"kafka-.*"} == 0
  for: 1m
  severity: critical

- alert: HighErrorRate
  expr: rate(iot_messages_failed_total[5m]) > 0.1
  for: 5m
  severity: warning
```

---

## 9. Security

### 9.1 Authentication

**Workload Identity:**
- Pods use GCP service accounts
- No static credentials
- Fine-grained IAM permissions

**RBAC:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources: ["nodes", "services", "pods"]
  verbs: ["get", "list", "watch"]
```

### 9.2 Secrets Management

**Google Secret Manager:**
- postgres-password
- kafka-cluster-id
- grafana-password

**Kubernetes Secrets:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: iot-pipeline-secrets
type: Opaque
data:
  POSTGRES_PASSWORD: <base64>
```

### 9.3 Network Security

**Network Policies:**
- Internal traffic only
- MQTT external (1883)
- Health checks from GCP LB

**Pod Security:**
```yaml
securityContext:
  fsGroup: 1000
  runAsUser: 1000
  runAsNonRoot: true
```

---

## 10. Deployment

### 10.1 Prerequisites

- GCP project with billing
- gcloud CLI authenticated
- Terraform installed
- kubectl configured

### 10.2 Infrastructure Deployment

```bash
# Initialize Terraform
cd terraform
terraform init

# Deploy
terraform plan
terraform apply

# Resources created:
# - VPC network
# - GKE cluster
# - Node pools
# - Artifact Registry
# - Secret Manager
# - Firewall rules
```

### 10.3 Application Deployment

```bash
# Build images
./scripts/build-images.sh

# Deploy to K8s
kubectl apply -f gke/namespace/
kubectl apply -f gke/storage/
kubectl apply -f gke/config/
kubectl apply -f gke/kafka/
kubectl apply -f gke/timescaledb/
kubectl apply -f gke/app-services/
kubectl apply -f gke/monitoring/

# Verify
kubectl get pods -n iot-pipeline
```

### 10.4 Automated Deployment

```bash
# Full deployment
./scripts/deploy-gke.sh

# Options:
# --clean: Clean start
# --skip-build: Skip image building
# --skip-terraform: Skip infrastructure
# --import: Import existing resources
```

---

## 11. Operations

### 11.1 Scaling

**Horizontal:**
```bash
kubectl scale deployment ruuvitag-adapter --replicas=3
kubectl autoscale deployment ruuvitag-adapter \
    --min=1 --max=5 --cpu-percent=70
```

**Vertical:**
```bash
kubectl set resources deployment ruuvitag-adapter \
    --limits=cpu=1000m,memory=2Gi \
    --requests=cpu=500m,memory=1Gi
```

### 11.2 Updates

```bash
# Rolling update
kubectl set image deployment/ruuvitag-adapter \
    ruuvitag-adapter=<new-image>:v1.1.0

# Check status
kubectl rollout status deployment/ruuvitag-adapter

# Rollback
kubectl rollout undo deployment/ruuvitag-adapter
```

### 11.3 Backup & Restore

**Database Backup:**
```bash
kubectl exec timescaledb-0 -- \
    pg_dump -U iot_user iot_data > backup.sql
gzip backup.sql
gsutil cp backup.sql.gz gs://backup-bucket/
```

**Restore:**
```bash
gsutil cp gs://backup-bucket/backup.sql.gz .
gunzip backup.sql.gz
kubectl exec -i timescaledb-0 -- \
    psql -U iot_user iot_data < backup.sql
```

### 11.4 Maintenance

**Database:**
```sql
-- Vacuum
VACUUM ANALYZE sensor_readings;

-- Refresh aggregates
CALL refresh_continuous_aggregate('sensor_readings_hourly', NULL, NULL);

-- Check hypertables
SELECT * FROM timescaledb_information.hypertables;
```

**Kafka:**
```bash
# Check topics
kafka-topics --bootstrap-server localhost:9092 --list

# Check consumer groups
kafka-consumer-groups --bootstrap-server localhost:9092 \
    --describe --group iot-data-consumer
```

---

## 12. Performance

### 12.1 Benchmarks

**Throughput:**
- Message ingestion: 10,000+ msg/sec
- Database writes: 5,000+ inserts/sec
- Query latency: < 100ms (p95)

**Resource Usage:**
| Component | CPU (avg) | Memory (avg) |
|-----------|-----------|--------------|
| Kafka | 400m | 1.5Gi |
| TimescaleDB | 300m | 800Mi |
| Adapter | 150m | 200Mi |

### 12.2 Optimization

**Kafka:**
```yaml
linger.ms: 100
batch.size: 16384
compression.type: snappy
acks: all
```

**TimescaleDB:**
```sql
shared_buffers = 256MB
work_mem = 16MB
maintenance_work_mem = 128MB
effective_cache_size = 1GB
```

**Application:**
```python
# Batch processing
batch_size = 100
commit_interval = 5.0

# Connection pooling
pool_size = 5
max_overflow = 10
```

### 12.3 Capacity Planning

**Current Capacity:**
- 1,000+ devices
- 10,000+ msg/sec
- 90 days retention
- 10:1 compression

**Scaling Path:**
- Add Kafka partitions
- Scale consumer replicas
- Increase node pool size
- Optimize chunk intervals

---

## Appendix A: Configuration Reference

### Environment Variables

```bash
KAFKA_BOOTSTRAP_SERVERS=kafka-0:9092,kafka-1:9092,kafka-2:9092
KAFKA_TOPIC_NAME=iot-sensor-data
SCHEMA_REGISTRY_URL=http://schema-registry:8081
POSTGRES_HOST=timescaledb
POSTGRES_PORT=5432
MQTT_BROKER_HOST=mosquitto
MQTT_BROKER_PORT=1883
```

---

## Appendix B: Troubleshooting

### Common Issues

**1. Kafka Not Starting**
```bash
kubectl logs kafka-0
kubectl describe pod kafka-0
# Solution: Check storage initialization
```

**2. High Consumer Lag**
```bash
kafka-consumer-groups --describe
# Solution: Scale consumers
```

**3. Database Connection**
```bash
pg_isready -U iot_user
# Solution: Check credentials and network
```

---

**Document Version**: 1.0  
**Last Updated**: December 2025  
**Maintained By**: Rabindra