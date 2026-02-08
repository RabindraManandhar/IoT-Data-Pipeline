# IoT Data Pipeline - Technical Documentation

**Version**: 1.0.0  
**Date**: December 2025  
**Author**: Rabindra Manandhar  
**Status**: Development

---

This document provides comprehensive technical documentation for an IoT data pipeline deployed on Google Kubernetes Engine. The system processes real-time environmental sensor data from RuuviTag devices through ESP32 gateways.

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

A scalable and fault-tolerant data pipeline built on Google Kubernetes Engine (GKE) that processes real-time IoT sensor data from RuuviTag devices through ESP32 gateway, utilizing  Kafka for distributed streaming, TimescaleDB for time-series storage, and comprehensive monitoring with Prometheus and Grafana.

This project implements an end-to-end IoT data pipeline capable of ingesting, processing, storing, and visualizing sensor data at scale. It composes of the following components:

- `Real-Time Data Collection`: Collects real-time data with real IoT devices - specifically RuuviTags as BLE sensors, an ESP32 as a gateway and Mosquitto MQTT Broker for IoT device communication.
- `Avro Serialization`: Uses RuuviTag Adapter to transform MQTT messages into Kafka-compatible format with Avro serialization. Also uses Schema Registry to manage Avro schemas for data validation.
- `Data Ingestion`: Uses Confluet-Kafka for reliable and scalable data ingestion.
- `Data Storage`: Uses TimescaleDB for time-series data storage with automatic archiving.
- `Monitoring & Observability`: Comprehensive monitoring with Prometheus, Grafana, and AlertManager.
- `Alerting`: Real-time alerts for systems and data anomalies.

### 1.2 Key Features

- `Real-time Processing`: Sub-second latency from sensor to database.
- `High availability`: 3-node Kafka cluster with replication factor 3.
- `Time-series Optimization`: TimescaleDB with automatic compression and retention.
- `Schema Evolution`: Avro serialization with backward compabiliity. 
- `Comprehensive Monitoring`: Prometheus metrics with Grafana dashboards.
- `Containerization and Orchestration`: Docker containers and GKE orchestration.
- `Infrastructure as Code`: Complete Terraform configuration

### 1.3 Key Metrics

- **Components**: 15 pods across 10 services
- **Throughput**: 10,000+ messages/second
- **Data Retention**: 90 days with automatic archival
- **Availability**: 99.9% uptime with 3x replication
- **Latency**: < 1 second end-to-end

### 1.4 Use Cases

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
| Kafka Brokers | 3 | 300m | 512Mi |
| Schema Registry | 1 | 250m | 512Mi |
| TimescaleDB | 1 | 300m | 512Mi |
| Mosquitto | 1 | 100m | 64Mi |
| RuuviTag Adapter | 1 | 200m | 256Mi |
| Kafka Consumer | 1 | 200m | 256Mi |
| TimescaleDB Sink | 1 | 200m | 256Mi |
| Prometheus | 1 | 200m | 256Mi |
| Grafana | 1 | 100m | 128Mi |
| AlertManager | 1 | 50m | 64Mi |
| Kafka JMX Exporter | 1 | 50m | 64Mi |
| Mosquito Exporter | 1 | 250m | 32Mi |
| Node Exporter |1| 25m | 32Mi |
| Postgres Exporter | 1 | 50m | 64Mi |

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
- confluent-kafka==2.9.0
- confluent-kafka[avro]==2.9.0
- python-dotenv==1.1.0
- pydantic==2.11.3
- pydantic-settings==2.8.1
- avro-python3==1.10.2 # Avro serialization
- fastavro==1.10.0 # Fast Avro implementation
- requests==2.32.3 # For Schema Registry HTTP requests
- pyyaml==6.0.2 # For YAML configuration parsing
- paho-mqtt==1.6.1
- psycopg2-binary==2.9.9
- sqlalchemy==2.0.23
- alembic==1.13.1 # Database migration tool
- prometheus-client==0.20.0
- loguru==0.7.3
- psutil==5.9.8 # System and process utilities for monitoring
- flask==3.0.0 # Web framework for metrics endpoints and health check
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
| AlertManager | standard-rwo | 5Gi | HDD |
| Mosquitto | standard-rwo | 2Gi | HDD |

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
    "timestamp": "2025-12-24T09:02:50.847522+00:00",
    "temperature": 22.5,
    "humidity": 45.2
}

# Output: Multiple Kafka messages
[
    {
        "device_id": "AA:BB:CC:DD:EE:FF_temperature",
        "device_type": "temperature_sensor",
        "timestamp": "2025-12-24T09:02:50.847522+00:00",
        "value": 22.5,
        "unit": "°C"
    },
    {
        "device_id": "AA:BB:CC:DD:EE:FF_humidity",
        "device_type": "humidity_sensor",
        "timestamp": "2025-12-24T09:02:50.847522+00:00",
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

**Key**: `device_id` \
**Hash-based**: Ensures same sensor → same partition \
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
- `iot_messages_received_total`
- `iot_messages_processed_total`

**Kafka Metrics (JMX):**
- `kafka_consumer_messages_consumed_created`
- `kafka_consumer_messages_consumed_total`

**Database Metrics:**
- `pg_stat_database_numbackends`
- `pg_database_size_bytes`

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

### 8.4 Database Monitoring

```sql
-- Connect to TimescaleDB using psql cli
kubectl exec -it timescaledb-0 psql -n iot-pipeline -- psql -U iot_user -d iot_data

-- Basic Time-series analysis
-- Recent sensor readings (last 24 hours)
SELECT 
    device_id,
    device_type,
    value,
    unit,
    timestamp,
    is_anomaly
FROM sensor_readings
WHERE timestamp >= NOW() - INTERVAL '24 hours'
ORDER BY timestamp DESC
LIMIT 10;

-- Time-series data for specific device
SELECT 
    timestamp,
    value,
    unit,
    battery_level,
    is_anomaly
FROM sensor_readings
WHERE device_id = 'c6:8d:c6:26:39:a6_temperature'
    AND timestamp >= NOW() - INTERVAL '7 days'
ORDER BY timestamp DESC;

-- Data within specific time range
SELECT device_id, device_type, AVG(value) as avg_value, MIN(value) as min_value,
    MAX(value) as max_value,
    COUNT(*) as reading_count
FROM sensor_readings
WHERE timestamp BETWEEN '2025-08-08' AND '2025-08-11'
    AND device_type = 'temperature_sensor'
GROUP BY device_id, device_type
ORDER BY avg_value DESC;

-- Time Bucketing Queries
-- Hourly averages for the last week
SELECT 
    time_bucket('1 hour', timestamp) AS hour_bucket,
    device_id,
    device_type,
    AVG(value) as avg_value,
    MIN(value) as min_value,
    MAX(value) as max_value,
    COUNT(*) as readings_count,
    COUNT(CASE WHEN is_anomaly THEN 1 END) as anomaly_count
FROM sensor_readings
WHERE timestamp >= NOW() - INTERVAL '7 days'
    AND device_type = 'temperature_sensor'
GROUP BY hour_bucket, device_id, device_type
ORDER BY hour_bucket DESC, device_id;

-- Daily aggregation with multiple metrics
SELECT 
    time_bucket('1 day', timestamp) AS day_bucket,
    device_type,
    COUNT(DISTINCT device_id) as unique_devices,
    AVG(value) as avg_value,
    STDDEV(value) as std_deviation,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY value) as median_value,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY value) as p95_value,
    COUNT(*) as total_readings,
    COUNT(CASE WHEN is_anomaly THEN 1 END) as anomaly_count,
    (COUNT(CASE WHEN is_anomaly THEN 1 END) * 100.0 / COUNT(*)) as anomaly_percentage
FROM sensor_readings
WHERE timestamp >= NOW() - INTERVAL '30 days'
GROUP BY day_bucket, device_type
ORDER BY day_bucket DESC, device_type;

-- 15-minute intervals for real-time monitoring
SELECT 
    time_bucket('15 minutes', timestamp) AS time_bucket,
    device_id,
    AVG(value) as avg_value,
    last(value, timestamp) as latest_value,
    last(battery_level, timestamp) as latest_battery,
    MAX(timestamp) as last_reading_time
FROM sensor_readings
WHERE timestamp >= NOW() - INTERVAL '4 hours'
    AND device_type IN ('temperature_sensor', 'humidity_sensor')
GROUP BY time_bucket, device_id
ORDER BY time_bucket DESC, device_id;

-- Advanced Time-Series Analytics
-- Gap detection (missing data periods longer than 30 minutes)
WITH time_series AS (
    SELECT 
        device_id,
        timestamp,
        LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp) as prev_timestamp,
        timestamp - LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp) as time_gap
    FROM sensor_readings
    WHERE device_id = 'c6:8d:c6:26:39:a6_temperature'
        AND timestamp >= NOW() - INTERVAL '7 days'
)
SELECT 
    device_id,
    prev_timestamp,
    timestamp,
    time_gap,
    EXTRACT(EPOCH FROM time_gap) / 60 as gap_minutes
FROM time_series
WHERE time_gap > INTERVAL '30 minutes'
ORDER BY timestamp DESC;

-- Moving averages and trends
SELECT
    device_id,
    timestamp,
    value,
    AVG(value) OVER (
        PARTITION BY device_id 
        ORDER BY timestamp 
        ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ) as moving_avg_12_readings,
    value - LAG(value, 1) OVER (
        PARTITION BY device_id 
        ORDER BY timestamp
    ) as value_change
FROM sensor_readings
WHERE device_type = 'temperature_sensor'
    AND timestamp >= NOW() - INTERVAL '24 hours'
ORDER BY device_id, timestamp DESC;

-- Rate of change detection
SELECT 
    device_id,
    timestamp,
    value,
    LAG(value) OVER (PARTITION BY device_id ORDER BY timestamp) as prev_value,
    LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp) as prev_timestamp,
    (value - LAG(value) OVER (PARTITION BY device_id ORDER BY timestamp)) / 
    EXTRACT(EPOCH FROM (timestamp - LAG(timestamp) OVER (PARTITION BY device_id ORDER BY timestamp))) * 3600 
    as rate_per_hour
FROM sensor_readings
WHERE device_type = 'temperature_sensor'
    AND timestamp >= NOW() - INTERVAL '6 hours'
ORDER BY device_id, timestamp DESC;

-- Query Continuous Aggregates
-- Query hourly continous aggregates
SELECT 
    bucket,
    device_id,
    device_type,
    reading_count,
    avg_value,
    min_value,
    max_value,
    anomaly_count,
    latest_battery_level
FROM sensor_readings_hourly
WHERE bucket >= NOW() - INTERVAL '7 days'
    AND device_type = 'temperature_sensor'
ORDER BY bucket DESC, device_id;

-- Query daily continuous aggregates
SELECT 
    bucket,
    device_id,
    device_type,
    reading_count,
    avg_value,
    min_value,
    max_value,
    anomaly_count,
    first_battery_level,
    latest_battery_level,
    (latest_battery_level - first_battery_level) as battery_change
FROM sensor_readings_daily
WHERE bucket >= NOW() - INTERVAL '30 days'
ORDER BY bucket DESC, avg_value DESC;

-- Calculate latency from sensor emission to database insertion
SELECT 
    device_id,
    timestamp as sensor_emission_time,
    created_at as db_insertion_time,
    EXTRACT(EPOCH FROM (created_at - timestamp)) * 1000 AS latency_ms
FROM sensor_readings
WHERE timestamp >= NOW() - INTERVAL '24 hours'
ORDER BY timestamp DESC
LIMIT 10;

-- Get latency statistics (median, p95, p99)
WITH latency_data AS (
    SELECT 
        EXTRACT(EPOCH FROM (created_at - timestamp)) * 1000 AS latency_ms
    FROM sensor_readings
    WHERE timestamp >= NOW() - INTERVAL '24 hours'
        AND created_at IS NOT NULL
        AND timestamp IS NOT NULL
)
SELECT 
    COUNT(*) as sample_size,
    ROUND(AVG(latency_ms)::numeric, 2) as mean_latency_ms,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) as median_latency_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) as p95_latency_ms,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) as p99_latency_ms,
    ROUND(MIN(latency_ms)::numeric, 2) as min_latency_ms,
    ROUND(MAX(latency_ms)::numeric, 2) as max_latency_ms,
    ROUND(STDDEV(latency_ms)::numeric, 2) as stddev_ms
FROM latency_data;

-- Latency distribution over time (hourly buckets)
WITH latency_data AS (
    SELECT 
        time_bucket('1 hour', timestamp) AS hour,
        EXTRACT(EPOCH FROM (created_at - timestamp)) * 1000 AS latency_ms
    FROM sensor_readings
    WHERE timestamp >= NOW() - INTERVAL '24 hours'
)
SELECT 
    hour,
    COUNT(*) as message_count,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) as median_ms,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) as p95_ms,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) as p99_ms
FROM latency_data
GROUP BY hour
ORDER BY hour DESC;


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
  resources:
  - nodes
  - nodes/proxy
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
- apiGroups:
  - extensions
  resources:
  - ingresses
  verbs: ["get", "list", "watch"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]

---

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: iot-pipeline
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
  # TimescaleDB Credentials
  POSTGRES_USER: "REPLACE_ME"
  POSTGRES_PASSWORD: "REPLACE_ME"
  POSTGRES_DB: "REPLACE_ME"

  # Grafana Credentials
  GRAFANA_USER: "REPLACE_ME"
  GRAFANA_PASSWORD: "REPLACE_ME"

  # Kafka KRaft Cluster ID
  CLUSTER_ID: "REPLACE_ME"

  # Create the DSN for postgres-exporter
  DATA_SOURCE_NAME: "REPLACE_ME"
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

1. Hardware Requirements

    - RuuviTag sensors
    - ESP32 development board (with bluetooth and wireless compatibility)
    - Host/Developer Machine (Windows, Linux, or MacOS) for development and monitoring

2. Software Requirements

    2.1 For ESP32 Gateway
    
    - Toolchain to compile code for ESP32
    - Build tools - CMake and Ninja to build a full application for ESP32
    - ESP-IDF v4.4 or newer that essentially contains API (software libraries and source code) for ESP32 and scripts to operate the Toolchain
    
    2.2 For GKE
    
    - Docker (>=20.10)
    - Kubectl (>=1.27)
    - Google Cloud Platform Account with billing enabled
    - gcloud CLI (>=400.0.0)
    - Terraform

3. Network Requirements

    - WiFi network (2.4GHz for ESP32)
    - Available ports: 1883(MQQT), 9090(Prometheus), 3000(Grafana), 9093(AlertManager)

### 10.2 ESP-IDF Environment Setup

1. Linux/MacOS

    - Clone ESP-IDF (ESP32 IoT Development Framework) repository

        Follow the [official ESP-IDF installation guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/get-started/index.html) for your OS.

        ```bash
        mkdir -p ~/esp
        cd ~/esp
        git clone --recursive https://github.com/espressif/esp-idf.git
        cd ~/esp/esp-idf
        ./install.sh
        ```

    - Set environment variable to activate ESP-IDF (add this to .profile or .bashrc)
        
        ```bash
        . $HOME/esp/esp-idf/export.sh
        ```

        `NOTE`: This is a script that comes with ESP-IDF to set up the environmental variables and paths needed for ESP-IDF tools to work. It configures IDF_PATH, adds CMake, Ninja, Python environment, Xtensa-ESP32 toolchain, etc. to your PATH. Basically, this script prepares your shell session to use ESP-IDF.

        `NOTE`: This script is added to in your shell’s startup config file (i.e. .bashrc or .profile) so it runs automatically when a new shell session starts, and you do not need to manually run the above script each time you open a new terminal.
        
        `NOTE`: How to add the script to your startup config file?
        
        ```
        nano ~/.bashrc
        ```

        Add this line at the bottom of the file:

        . $HOME/esp/esp-idf/export.sh

        
        Then, reload your shell so the changes take effect:
        
        ```
        source ~/.bashrc
        ```

        Now, every new terminal will have ESP-IDF ready to use.
        

2. Windows

    - Download the ESP-IDF Tools Installer from [official ESP-IDF installation guide](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/get-started/index.html)
    - Follow the installer and follow the instructions
    - Open the ESP-IDF Command Prompt from the Start menu

### 10.3 Project Setup

1. Cloning repository.

    - Clone the project repo and navigate to the project's root directory

        ```bash
        clone <repository_url>
        cd iot-data-pipeline
        ```
    
        Note: You are now in the root directory of the project "iot-data-pipeline"

### 10.4 ESP32 Gateway Implementation

1. ESP32 Gateway Configuration

    - From the project's root directory, navigate to ESP32 gateway project
        
        ```bash
        cd esp32/ruuvitag_gateway
        ```

    - Configure your Wi-Fi and MQTT settigns
        
        Create a `config.h` file inside the main folder. Copy the contents of main/config.h.example to the main/config.h and change REPLACE_ME in the following variables:
        
        ```
        #define WIFI_SSID			“REPLACE_ME”
        #define WIFI_PASSWORD		“REPLACE_ME”
        #define MQTT_BROKER_URL	    “mqtt://REPLACE_ME:1883”
        ```

        Include the config.h file in your main/main.c source
        
        ```
        #include "config.h"
        ```

    - Set ESP32 target
        ```bash
        idf.py set-target esp32
        ```
    
    - Enable Bluetooth in menu configuration
        
        ```
        idf.py menuconfig
        ```

        This opens a configuration window. In the configuration menu:
        - Navigate to `Component config` -> `Bluetooth` -> `Bluetooth`
        - Enable `Bluetooth`
        - Then navigate to `Bluetooth` -> `Host (Bluedroid -- Dual-mode)`
        - Enable `Bluedroid (the Bluetooth stack)`
        - Save the configuration and exit
        
            `Note`: Use left arrow key to navigate left and right arrow key to navigate right.\
            `Note`: Use spacebar to select/unselect the option\
            `Note`: Keep pressing ‘ESC’ key to leave menu without saving\
            `Note`: Press ‘Q’ and then ‘Y’ to save the configuration and quit the configuration menu

    - Enable Partition Table in menu configuration

        When the compiled binary size exceeds the available space in the flash partition, it gives overflow error. To fix this issue,
        - Reduce the size of the binary
        - Increase the size of the partition

        Increasing the size of the partition is more straightforward. We'll need to create a custom partition table that increases the size of the factory partition.
        
        In ESP-IDF, partition table define how flash memory is allocated. It is configured by enabling Partition Table in the menu configuration:
        
        ```
        idf.py menuconfig
        ```

        This opens a menu configuration window. In the menuconfig interface:
        - Navigate to `Partition Table` → `Partition Table`
        - Enable `Custom partition table CSV`
        - Save the configuration and exit

        After enabling `Custom partition table CSV`, you need to create a `partitions.csv` with proper partition sizes in the esp32/ruuvitag_gateway/main directory. You can use the example partitions.csv file given in the project.
        
2. Build, flash and monitor
        
    ```bash
    idf.py build
    idf.py -p <PORT> flash 
    idf.py -p <PORT> monitor
    ```
    
    `Note`: `<PORT>` should be replaced with the serial/USB port your ESP32 is connected to.

    For macOS, 
    
    - /dev/cu.usbserial-xxxx
    - /dev/cu.SLAB_USBtoUART (Silicon Labs CP210x USB-UART bridge)
    - /dev/cu.usbmodemxxxx (CH340/CH9102 or Apple Silicon drivers)

    You can check by running:
    
    ```bash
    ls /dev/cu.*
    ```

    For Linux,

    - /dev/ttyUSB0, /dev/ttyUSB1, ... (CP210x, CH340 USB-to-UART adapters)
    - /dev/ttyACM0, /dev/ttyACM1, ... (CDC-ACM devices)

    You can check by running:
    
    ```bash
    dmesg | grep tty
    ```

    For Windows,
    - COM3, COM4, ... (varies depending on USB device)

    Check in Device Manager -> Ports (COM & LPT).

    `Note`: This will perform the followings:
    - ESP32 collects the real-time IoT data from RuuviTag sensors via BLE
    - ESP32 sends the collected data to the Kafka via MQTT protocol

3. MQTT Broker Configuration

    The MQTT broker service is set up as loadbalancer and you may need to:
    - Check MQTT broker logs in GKE
    - Test connectivity with MQTT clients

### 10.5 Google Kubernetes Engine (GKE) Deployment

1. GKE Configuration

    - Navigate to /gke/config folder inside the project's root directory.

        ```bash
        cd ../..
        cd gke/config
        ```
    
    - Generate a kafka_cluster_id using the following command
       
        ```bash
        docker run --rm confluentinc/cp-kafka:7.9.0 kafka-storage random-uuid
        ```

    - Generate a `secrets.yaml` file inside gke/config folder. Copy the contents of secrets.yaml.example to the secrets.yaml file and change the placeholder value "REPLACE_ME" for all variables.

        ```
        POSTGRES_USER: "REPLACE_ME"
        POSTGRES_PASSWORD: "REPLACE_ME"
        POSTGRES_DB: "REPLACE_ME"
        GRAFANA_USER: "REPLACE_ME"
        GRAFANA_PASSWORD: "REPLACE_ME"
        CLUSTER_ID: "REPLACE_ME"
        DATA_SOURCE_NAME: "REPLACE_ME"
        ```

        NOTE: Replace the placeholder value "REPLACE_ME" for the variable CLUSTER_ID with the kafka_cluster_id generated above.

2. Automatic GKE Deployment (Using bash script)

    - Navigate to /scripts folder in the project's /gke directory.

        ```bash
        cd ..
        cd scripts
        ```

    - Deploy the GKE project using deployment script.

        ```bash
        ./deploy-gke.sh

        # Options:
        # --clean: Clean start
        # --skip-build: Skip image building
        # --skip-terraform: Skip infrastructure
        # --import: Import existing resources
        ```

3. Manual GKE Deployment (ALTERNATIVE)

    a. Terraform Deployment

    - Navigate to terraform folder in the project's /gke directory.

        ```bash
        cd ..
        cd terraform
        ```

    - Deploy infrastructure in GKE.

        ```bash
        terraform init
        terraform validate
        terraform plan -out=tfplan
        terraform apply tfplan
        ```

    b. Build and Push images to Google Cloud's Artifact Registry.

    - Navigate to /scripts folder in the project's /gke directory.

        ```bash
        cd ..
        cd scripts
        ./build-images.sh
        ```
    
    c. Deploy Kubernetes resources.

    - Navigate to /gke folder in the project's root directory.

        ```bash
        cd ..
        cd gke
        ```

    - Run the following commands to deploy kubernetes resources.

        ```bash
        kubectl apply -f namespace/
        kubectl apply -f storage/
        kubectl apply -f config/
        kubectl apply -f kafka/
        kubectl apply -f timescaledb/
        kubectl apply -f schema-registry/
        kubectl apply -f mosquitto/
        kubectl apply -f app-services/
        kubectl apply -f monitoring/
        ```

4. Verify Deployment

    ```bash
    kubectl get pods -n iot-pipeline
    ```

### 10.6 Accessing Services

- Navigate to /scripts folder in the project's /gke directory.

    ```bash
    cd scripts
    ```

- Port forward all services.
    
    ```bash
    ./port-forward-all.sh

    # Access the following URLs:
    # Grafana:              http://localhost:3000
    # Prometheus:           http://localhost:9090
    # AlertManager:         http://localhost:9093
    # RuuviTag Adapter:     http://localhost:8002/metrics
    # Kafka Consumer:       http://localhost:8001/metrics
    # TimescaleDB Sink:     http://localhost:8003/metrics
    # Kafka JMX:            http://localhost:9101/metrics
    # PostgreSQL Exporter:  http://localhost:9187/metrics
    # Mosquitto Exporter:   http://localhost:9234/metrics
    ```

### 10.7 Cleanup

- Navigate to /gke folder in the project's root directory.

    ```bash
    cd ..
    cd gke
    ```

- Delete the kubernetes resources
    
    ```bash
    kubectl delete --force namespace iot-pipeline
    ```

- Navigate to /terraform folder in the project's /gke directory.

    ```bash
    cd ..
    cd terraform
    ``` 

- Delete the GKE infrastructure
    ```bash
    terraform destroy -auto-approve
    ```

---

## 11. Operations

### 11.1 Scaling

**Horizontal:**
```bash
kubectl scale deployment ruuvitag-adapter --replicas=3 -n iot-pipeline
kubectl autoscale deployment ruuvitag-adapter --min=1 --max=5 --cpu-percent=70 -n iot-pipeline
```

**Vertical:**
```bash
kubectl set resources deployment ruuvitag-adapter --limits=cpu=1000m,memory=2Gi --requests=cpu=500m,memory=1Gi -n iot-pipeline
```

### 11.2 Updates

```bash
# Rolling update
kubectl set image deployment/ruuvitag-adapter ruuvitag-adapter=<new-image>:v1.1.0 -n iot-pipeline

# Check status
kubectl rollout status deployment/ruuvitag-adapter -n iot-pipeline

# Rollback
kubectl rollout undo deployment/ruuvitag-adapter -n iot-pipeline
```

### 11.3 Backup & Restore

**Database Backup:**
```bash
kubectl exec timescaledb-0 -n iot-pipeline -- pg_dump -U iot_user iot_data > backup.sql
gzip backup.sql
gsutil cp backup.sql.gz gs://backup-bucket/
```

**Restore:**
```bash
gsutil cp gs://backup-bucket/backup.sql.gz .
gunzip backup.sql.gz
kubectl exec -i timescaledb-0 -n iot-pipeline -- psql -U iot_user iot_data < backup.sql
```

### 11.4 Maintenance

**Kafka:**
```sql
-- Check topics
kubectl exec -it -n iot-pipeline kafka-0 -- kafka-topics --bootstrap-server kafka-0.kafka-headless.iot-pipeline.svc.cluster.local:9092 --list

-- View messages on the topic
kubectl exec -it -n iot-pipeline kafka-0 -- kafka-console-consumer --bootstrap-server kafka-0.kafka-headless.iot-pipeline.svc.cluster.local:9092 --topic iot-sensor-data --from-beginning

-- Check consumer groups
kubectl exec -it -n iot-pipeline kafka-0 -- kafka-consumer-groups --bootstrap-server kafka-0.kafka-headless.iot-pipeline.svc.cluster.local:9092 --describe --group iot-data-consumer

-- Create topic autocreation
kubectl exec kafka-0 -n iot-pipeline -c kafka -- kafka-topics --bootstrap-server kafka-0.kafka-headless.iot-pipeline.svc.cluster.local:9092 --create --topic new-topic --partitions 1 --replication-factor 1
```

**Database:**
```sql
-- Connect to TimescaleDB using psql cli
kubectl exec -it timescaledb-0 -n iot-pipeline -- psql -U iot_user -d iot_data

-- Inside psql, list databases
iot_dat=# \l

-- Switch database
iot_data=# \c <database-name>

-- List tables, views, sequence
iot_data=# \d

-- List only tables
iot_data=# \dt

-- List all hypertables
iot_data=# select * from timescaledb_information.hypertables;

-- List chunks of a specific hypertable
iot_data=# SELECT * FROM timescaledb_information.chunks WHERE hypertable_name = '<hypertable-name>';

-- Check compression statistics
iot_data=# SELECT * FROM timescaledb_information.compression_settings;
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

**1. ESP32 Issues**

- Bluetooth Not Working
    - Ensure Bluetooth is enabled in the ESP-IDF configuration
    - Verify that the ESP32 module has Bluetooth capability and is properly initialized

- ESP32 not connecting to WiFi
    - Double-check the `SSID` and `password`
    - Ensure the WiFi network is 2.4 GHz (ESP32 doesn't support 5 GHz)
    - Check ESP32 serial monitor for connection errors

- No RuuviTag Data
    - Confirm RuuviTags are powered and broadcasting
    - Place RuuviTags closer to the ESP32 during testing
    - Check if the RuuviTags are using a supported data format (usually format 5)

**2. MQTT Issues**

- ESP32 not connecting to MQTT broker in docker
    - Verify the MQTT broker IP address is correct
    - Ensure no firewall is blocking port 1883
    - Ensure port 1883 is open (If mosquitto broker service is active in local machine at port 1883, stop the service in the local machine)
    - Check that the MQTT broker is running and accessible from the ESP32
    - Start port-forward (keep this terminal open)
        ```bash
        kubectl port-forward -n iot-pipeline --address 0.0.0.0 svc/mosquitto 1883:1883
        ```

- No data in MQTT topic
    - Check ESP32 logs for MQTT publish errors
    - Verify topic name matches between ESP32 and adapter

**3. Kafka Issues**

- RuuviTag adapter not connecting to Kafka
    - Check Kafka broker status
    - Verify configuration parameters
    - Look for connection errors in logs

- Schema validation errors
    - Verify the data format matches the schema
    - Check Schema Registry status
    - Review adapter transformation logic

- Brokers Won't Start
    - Check logs for configuration errors:
        ```bash
        kubectl logs <kafka-pod> -n iot-pipeline
        kubectl describe <kafka-pod> -n iot-pipeline
        ```
- Kafka Connection Issues
    - Ensure all containers are on the same Docker network
    - Check that Kafka brokers have had enough time to initialize before producers/consumers connect
    - Verify the advertised listeners are configured correctly for both internal and external access

- High Consumer Lag
    ```bash
    kubectl exec -it -n iot-pipeline kafka-0 -- kafka-consumer-groups --bootstrap-server kafka-0.kafka-headless.iot-pipeline.svc.cluster.local:9092 --describe --group iot-data-consumer
    ```

**4. TimescaleDB Issues**

- Database Connection Failures
    - Check TimescaleDB service status:
        ```bash
        kubectl logs <timescaledb_pod> -n iot-pipeline
        kubectl describe <timescaledb_pod> -n iot-pipeline
        ```
    - Verify database credentials
    - Ensure database initialization completed
    - Check network connectivity

- TimescaleDB Sink Not Working
    - Check sink service logs:
        ```bash
        kubectl logs <timescaledb-sink_pod> -n iot-pipeline
        kubectl describe <timescaledb-sink_pod> -n iot-pipeline
            ```
    - Verify Kafka connectivity from sink
    - Check database permissions
    - Monitor batch processing logs

- SQLAlchemy 'metadata' Attribute Error
    - This has been fixed by renaming the column to `device_metadata`
    - If you have existing data, run the migration:
        ```bash
        kubectl exec -it timescaledb psql -U iot_user -d iot_data -f /docker-entrypoint-initdb.d/02-migrate.sql
        ```

**5. Producer/Consumer Issues**

- Check the logs for connection errors or exceptions
- Ensure the topic has been created
- Verify environment variables are set correctly

**6. Performance Issues**

- High latency or lag
    - Increase Kafka partitions for better parallelism
    - Tune TimescaleDB batch sizes
    - Monitor resource usage: docker stats
    - Scale consumers horizontally
    - Check network bandwidth

- Memory or disk issues
    - Implement data retention policies
    - Enable TimescaleDB compression
    - Monitor disk usage
    - Adjust batch sizes and intervals

**7. Monitoring Issues**
    
- Prometheus Not Collecting Metrics

    - Check service endpoints: curl http://localhost:9090/metrics
    - Verify scrape configuration in prometheus.yml
    - Check Prometheus logs:
        ```bash
        kubectl logs <prometheus_pod> -n iot-pipeline
        ```

- Grafana Dashboard Issues

    - Verify Prometheus datasource connection
    - Check dashboard JSON configuration
    - Review Grafana logs:
        ```bash
        kubectl logs <grafana_pod> -n iot-pipeline
        ```

- Missing Metrics

    - Confirm service metrics exposition
    - Check network connectivity between services
    - Verify metrics server startup in application logs

- AlertManager Not Sending Alerts

    - Check alert rule evaluation in Prometheus
    - Verify AlertManager configuration
    - Test SMTP configuration with Mailpit

- Common Monitoring Problems

    - High Memory Usage: Monitor prometheus_tsdb_head_samples
    - Missing Data Points: Check scrape_duration vs scrape_interval
    - Dashboard Loading Slowly: Optimize query time ranges
    - Alerts Not Firing: Verify expression evaluation in Prometheus

---

**Document Version**: 1.0  
**Last Updated**: December 2025  
**Maintained By**: Rabindra