# IoT Data Ingestion Pipeline on Kubernetes (with Minikube Cluster)

A scalable and fault-tolerant data pipeline built on Kubernetes  that processes real-time IoT sensor data from RuuviTag devices through ESP32 gateway, utilizing  Kafka for distributed streaming, TimescaleDB for time-series storage, and comprehensive monitoring with Prometheus and Grafana.

## Project Overview

This project implements an end-to-end IoT data pipeline capable of ingesting, processing, storing, and visualizing sensor data at scale. It composes of the following components:

- `Real-Time Data Collection`: Collects real-time data with real IoT devices - specifically RuuviTags as BLE sensors, an ESP32 as a gateway and Mosquitto MQTT Broker for IoT device communication.
- `Avro Serialization`: Uses RuuviTag Adapter to transform MQTT messages into Kafka-compatible format with Avro serialization. Also uses Schema Registry to manage Avro schemas for data validation.
- `Data Ingestion`: Uses Confluet-Kafka for reliable and scalable data ingestion.
- `Data Storage`: Uses TimescaleDB for time-series data storage with automatic archiving.
- `Monitoring & Observability`: Comprehensive monitoring with Prometheus, Grafana, and AlertManager.
- `Alerting`: Real-time alerts for systems and data anomalies.

## Key Features

- `Real-time Processing`: Sub-second latency from sensor to database.
- `High availability`: 3-node Kafka cluster with replication factor 3.
- `Time-series Optimization`: TimescaleDB with automatic compression and retention.
- `Schema Evolution`: Avro serialization with backward compabiliity.
- `Comprehensive Monitoring`: Prometheus metrics with Grafana dashboards.
- `Containerization and Orchestration`: Docker containers and k8s orchestration.
- `Infrastructure as Code`: Complete Terraform configuration

## Use Cases

- Real-time environmental monitoring
- Predictive maintenance
- Anomaly detection
- Historical trend analysis
- Multi-location sensor networks

## System Architecture

1. High-Level Architecture

    ```
    ┌─────────────────────────────────────────────────────────┐
    │                   Physical Layer                        │
    |                                                         |
    │        RuuviTag Sensors --▶ ESP32 Gateway               │
    └──────────────────────────┬──────────────────────────────┘
                            | MQTT (Port 1833)
    ┌──────────────────────────▼──────────────────────────────┐
    │               Application Layer (K8S)                   │
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

2. Component Distribution

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

3. Network Architecture

    **Core Kubernetes Networking**
    - Pod Network (Flat L3 Network) -> Implemented by Container Network Interface (CNI) (Flannel / Calico / bridge /etc.)
    - Service Networking (Virtual IPs and Load Balancing)
        - ClusterIP
        - Headless Services
        - kube-proxy (iptables / IPVS)
    - DNS-Based Service Discovery
        - CoreDNS
    -Ingress
        - LoadBalancer


    **Service Mesh:**
    - mosquitto.iot-pipeline.svc.cluster.local:1883
    - kafka-0.kafka-headless.iot-pipeline.svc.cluster.local:9092,kafka-1.kafka-headless.iot-pipeline.svc.cluster.local:9092,kafka-2.kafka-headless.iot-pipeline.svc.cluster.local:9092
    - schema-registry.iot-pipeline.svc.cluster.local:8081
    - timescaledb.iot-pipeline.svc.cluster.local:5432

## Technologies Stack

1. Core Technologies

    | Category | Technology | Version | Purpose |
    |----------|-----------|---------|---------|
    | IoT Development Framework | ESP-IDF | Latest | IoT Sensor Programming |
    | Orchestration | Kubernetes | 1.27+ | Container management |
    | Streaming | Confluent Kafka | 7.9.0 | Event streaming |
    | Schema | Schema Registry | 7.9.0 | Avro management |
    | Database | TimescaleDB | PG 16 | Time-series storage |
    | Broker | Mosquitto | 2.0 | MQTT messaging |
    | Monitoring | Prometheus | 2.48 | Metrics collection |
    | Visualization | Grafana | Latest | Dashboards |

2. Python Stack
    ```bash
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

## Prerequisites

1. Hardware Requirements

    - RuuviTag sensors
    - ESP32 development board (with bluetooth and wireless compatibility)
    - Host/Developer Machine (Windows, Linux, or MacOS) for development and monitoring

2. Software Requirements

    2.1 For ESP32 Gateway
    
    - Toolchain to compile code for ESP32
    - Build tools - CMake and Ninja to build a full application for ESP32
    - ESP-IDF v4.4 or newer that essentially contains API (software libraries and source code) for ESP32 and scripts to operate the Toolchain
    
    2.2 For K8s
    
    - Docker -> Builds images, Used by Minikube as container runtime
    - Kubectl -> Deploys and manages Kubernetes resources
    - Minikube -> Local Kubernetes cluster
    - Git - Source control

3. Network Requirements

    - WiFi network (2.4GHz for ESP32)
    - Available ports: 1883(MQQT), 9090(Prometheus), 3000(Grafana), 9093(AlertManager)

## ESP-IDF Environment Setup

If you haven't installed ESP-IDF yet, follow these steps:

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

## Quick Start

### Project Setup:

1. Cloning repository.

    - Clone the project repo and navigate to the project's root directory

        ```bash
        clone <repository_url>
        cd iot-data-pipeline
        ```
    
        Note: You are now in the root directory of the project "iot-data-pipeline"

### ESP32 Gateway Implementation

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
    - Check MQTT broker logs in K8S
    - Test connectivity with MQTT clients

### Local Kubernetes Deployment

1. K8S Configuration

    - Navigate to /docker folder inside the project's root directory.
        
        ```bash
        cd ../..
        cd docker
        ```
    
    - Generate a kafka_cluster_id using the following command
       
        ```bash
        docker run --rm confluentinc/cp-kafka:7.9.0 kafka-storage random-uuid
        ```

    - Create an environment file named .env inside /docker directory. Create the following CLUSTER_ID variable with the value of the kafka_cluster_id generated above.
        
        ```bash
        CLUSTER_ID="kafka_cluster_id"
        ```

        Also, create all other necessary environmental variables in the .env file.

    - Navigate to /k8s/config folder inside the project's root directory.

        ```bash
        cd ..
        cd k8s/config
        ```
    
    - Generate a `secrets.yaml` file inside k8s/config folder. Copy the contents of secrets.yaml.example to the secrets.yaml file and change the placeholder value "REPLACE_ME" for all variables.

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

2. Automatic Kubernetes Deployment (Using bash script)

    - Navigate to /scripts folder in the project's root directory.

        ```bash
        cd ..
        cd scripts
        ```

    - Deploy the Kubernetes project using deployment script.

        ```bash
        ./deploy-k8s.sh
        ```

3. Manual K8S Deployment (ALTERNATIVE)

    a. Build and Push images to Docker Hub Registry.

    - Navigate to /scripts folder in the project's /k8s directory.

        ```bash
        cd ..
        cd scripts
        ./build-images.sh
        ```
    
    c. Deploy Kubernetes resources.

    - Navigate to /k8s folder in the project's root directory.

        ```bash
        cd ..
        cd k8s
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

## Accessing Services

- Navigate to /scripts folder in the project's /k8s directory.

    ```bash
    cd ..
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

## Cleanup

1. Automatic Kubernetes Resources Deletion (Using bash script)

    - In /scripts folder, run the following bash script to delete all kubernetes resources

        ```bash
        ./teardown.sh
        ```

2. Manual Kubernetes Resources Deletion (ALTERNATIVE)

    - Navigate to /k8s folder in the project's root directory
        
        ```bash
        cd ..
        ```

    - Delete all kubernetes resources using the following command
        ```bash
        kubectl delete --force namespace iot-pipeline
        ```

## Documentation

See [TECHNICAL_DOCUMENTATION.md](./TECHNICAL_DOCUMENTATION.md) for detailed technical information.