#!/bin/bash
# Complete IoT Data Pipeline Startup Script
# Starts all services in the correct order with health checks

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker/docker-compose.yml"
MAX_WAIT_TIME=300  # 5 minutes max wait for services

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗${NC} $1"
}

# Function to check MQTT broker health
check_mqtt_health() {
    local max_attempts=30
    local attempt=1
    
    log "Checking MQTT broker health..."
    
    while [ $attempt -le $max_attempts ]; do
        # Try multiple methods to check MQTT broker
        
        # Method 1: Check if port is accessible using telnet/nc
        if command -v nc >/dev/null 2>&1; then
            if nc -z localhost 1883 2>/dev/null; then
                log_success "MQTT broker port 1883 is accessible"
                return 0
            fi
        elif command -v telnet >/dev/null 2>&1; then
            if timeout 5 telnet localhost 1883 </dev/null 2>/dev/null | grep -q "Connected"; then
                log_success "MQTT broker is accessible via telnet"
                return 0
            fi
        fi
        
        # Method 2: Check Docker container health
        if docker ps --filter "name=mosquitto" --filter "health=healthy" --quiet | grep -q .; then
            log_success "MQTT broker container is healthy"
            return 0
        fi
        
        # Method 3: Check if container is running and port is bound
        if docker ps --filter "name=mosquitto" --format "table {{.Names}}\t{{.Status}}" | grep -q "mosquitto.*Up"; then
            # Check if port is bound
            if docker port mosquitto 1883 >/dev/null 2>&1; then
                log_success "MQTT broker container is running with port bound"
                return 0
            fi
        fi
        
        # Method 4: Try to use mosquitto_pub if available in container
        if docker exec mosquitto mosquitto_pub -h localhost -t "healthcheck" -m "test" >/dev/null 2>&1; then
            log_success "MQTT broker accepts publish commands"
            return 0
        fi
        
        if [ $((attempt % 5)) -eq 0 ]; then
            log "Waiting for MQTT broker... (attempt $attempt/$max_attempts)"
            log "You can check MQTT broker logs with: docker-compose logs mosquitto"
        fi
        
        sleep 10
        ((attempt++))
    done
    
    log_error "MQTT broker failed to become ready after $max_attempts attempts"
    log "Troubleshooting steps:"
    log "1. Check container status: docker-compose ps mosquitto"
    log "2. Check container logs: docker-compose logs mosquitto"
    log "3. Check port binding: docker port mosquitto"
    log "4. Check if port 1883 is already in use: netstat -an | grep 1883"
    return 1
}

# Function to wait for service to be ready
wait_for_service() {
    local service_name="$1"
    local check_cmd="$2"
    local timeout=${3:-$MAX_WAIT_TIME}
    
    log "Waiting for $service_name to be ready..."
    
    local count=0
    while [ $count -lt $timeout ]; do
        if eval "$check_cmd" >/dev/null 2>&1; then
            log_success "$service_name is ready"
            return 0
        fi
        sleep 5
        count=$((count + 5))
    done
    
    log_error "$service_name is not ready after ${timeout} seconds"
    return 1
}

# Function to check if all required JARs exist
check_required_jars() {
    log "Checking required JAR files..."
    
    local required_jars=(
        "flink-connector-kafka-3.2.0-1.19.jar"
        "flink-connector-files-1.19.1.jar"
        "flink-sql-connector-kafka-3.2.0-1.19.jar"
        "flink-avro-1.19.1.jar"
        "flink-parquet-1.19.1.jar"
        "hadoop-aws-3.3.6.jar"
        "aws-java-sdk-bundle-1.12.728.jar"
        "iceberg-flink-runtime-1.19-1.9.0.jar"
        "postgresql-42.7.1.jar"
    )
    
    local missing_jars=()
    
    for jar in "${required_jars[@]}"; do
        if [ ! -f "$PROJECT_ROOT/jars/$jar" ]; then
            missing_jars+=("$jar")
        fi
    done
    
    if [ ${#missing_jars[@]} -gt 0 ]; then
        log_warning "Missing JAR files detected: ${missing_jars[*]}"
        log "Running JAR download script..."
        
        if [ -f "$PROJECT_ROOT/scripts/download_flink_jars.sh" ]; then
            cd "$PROJECT_ROOT"
            bash scripts/download_flink_jars.sh
        else
            log_error "JAR download script not found. Please run it manually."
            return 1
        fi
    else
        log_success "All required JAR files are present"
    fi
}

# Function to setup directories
setup_directories() {
    log "Setting up required directories..."
    
    local dirs=(
        "$PROJECT_ROOT/jars"
        "$PROJECT_ROOT/logs"
        "$PROJECT_ROOT/data"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log "Created directory: $dir"
        fi
    done
    
    log_success "Directory setup complete"
}

# Function to check Docker and Docker Compose
check_docker() {
    log "Checking Docker and Docker Compose..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    log_success "Docker and Docker Compose are available"
}

# Function to cleanup existing containers
cleanup_existing() {
    log "Cleaning up existing containers..."
    
    cd "$PROJECT_ROOT/docker"
    
    # Stop and remove existing containers
    if docker-compose ps -q &> /dev/null; then
        docker-compose down -v --remove-orphans
        log "Stopped existing containers"
    fi
    
    # Clean up any orphaned containers
    docker container prune -f &> /dev/null || true
    
    log_success "Cleanup complete"
}

# Function to start core services
start_core_services() {
    log "Starting core services (Kafka, Schema Registry, PostgreSQL, MinIO)..."
    
    cd "$PROJECT_ROOT/docker"
    
    # Start core infrastructure services
    docker-compose up -d kafka1 kafka2 kafka3 schema-registry postgres minio
    
    # Wait for Kafka cluster
    wait_for_service "Kafka Cluster" \
        "docker exec kafka-broker-1 kafka-topics --bootstrap-server kafka1:9092 --list"
    
    # Wait for Schema Registry
    wait_for_service "Schema Registry" \
        "curl -f http://localhost:8081/subjects"
    
    # Wait for PostgreSQL
    wait_for_service "PostgreSQL" \
        "docker exec postgres pg_isready -U iceberg -d iceberg_catalog"
    
    # Wait for MinIO and setup buckets
    wait_for_service "MinIO" \
        "curl -f http://localhost:9000/minio/health/live"
    
    # Setup MinIO buckets
    log "Setting up MinIO buckets..."
    docker-compose up -d --no-deps mc
    sleep 10  # Give MC time to setup buckets
    
    log_success "Core services are running"
}

# Function to start Flink services
start_flink_services() {
    log "Starting Flink services..."
    
    cd "$PROJECT_ROOT/docker"
    
    # Start Flink JobManager
    docker-compose up -d flink-jobmanager
    
    # Wait for JobManager
    wait_for_service "Flink JobManager" \
        "curl -f http://localhost:8082/overview"
    
    # Start TaskManagers
    docker-compose up -d flink-taskmanager
    
    # Give TaskManagers time to register
    sleep 30
    
    log_success "Flink services are running"
}

# Function to start application services
start_application_services() {
    log "Starting application services..."
    
    cd "$PROJECT_ROOT/docker"
    
    # Start and check MQTT broker
    docker-compose up -d mosquitto
    if ! check_mqtt_health; then
        log_error "MQTT broker failed to start properly"
        log "Attempting to restart MQTT broker..."
        docker-compose restart mosquitto
        sleep 10
        if ! check_mqtt_health; then
            log_error "MQTT broker still not ready. Please check manually."
            log "Common issues:"
            log "1. Port 1883 might be in use by another service"
            log "2. Check if local mosquitto service is running: sudo systemctl status mosquitto"
            log "3. Stop local mosquitto: sudo systemctl stop mosquitto"
            return 1
        fi
    fi
    
    # Start other application services
    docker-compose up -d ruuvitag-adapter
    docker-compose up -d kafka-consumer
    docker-compose up -d kafka-ui
    
    log_success "Application services are running"
}

# Function to start streaming job
start_streaming_job() {
    log "Starting PyFlink streaming job..."
    
    cd "$PROJECT_ROOT/docker"
    
    # Start the Flink streaming job
    docker-compose up -d flink-streaming-job
    
    # Give the job time to start
    sleep 30
    
    # Check if job is running
    if docker-compose logs flink-streaming-job | grep -q "Streaming job started successfully"; then
        log_success "PyFlink streaming job is running"
    else
        log_warning "Streaming job may not have started properly. Check logs with:"
        log "docker-compose logs flink-streaming-job"
    fi
}

# Function to display service status
show_service_status() {
    log "Checking service status..."
    
    cd "$PROJECT_ROOT/docker"
    
    echo ""
    echo "=== Service Status ==="
    docker-compose ps
    
    echo ""
    echo "=== Access URLs ==="
    echo "• Kafka UI:           http://localhost:8080"
    echo "• Flink Web UI:       http://localhost:8082"
    echo "• MinIO Console:      http://localhost:9002 (admin/minioadmin)"
    echo "• Schema Registry:    http://localhost:8081"
    echo ""
    
    echo "=== Health Checks ==="
    
    # Kafka
    if curl -s http://localhost:8080 > /dev/null; then
        log_success "Kafka UI is accessible"
    else
        log_warning "Kafka UI is not accessible"
    fi
    
    # Flink
    if curl -s http://localhost:8082 > /dev/null; then
        log_success "Flink Web UI is accessible"
    else
        log_warning "Flink Web UI is not accessible"
    fi
    
    # MinIO
    if curl -s http://localhost:9002 > /dev/null; then
        log_success "MinIO Console is accessible"
    else
        log_warning "MinIO Console is not accessible"
    fi
    
    # Schema Registry
    if curl -s http://localhost:8081/subjects > /dev/null; then
        log_success "Schema Registry is accessible"
    else
        log_warning "Schema Registry is not accessible"
    fi
}

# Function to show logs
show_logs() {
    log "Recent logs from key services:"
    
    cd "$PROJECT_ROOT/docker"
    
    echo ""
    echo "=== Flink Streaming Job Logs ==="
    docker-compose logs --tail=20 flink-streaming-job
    
    echo ""
    echo "=== RuuviTag Adapter Logs ==="
    docker-compose logs --tail=10 ruuvitag-adapter
    
    echo ""
    echo "Use 'docker-compose logs -f <service-name>' to follow logs for a specific service"
}

# Function to run tests
run_basic_tests() {
    log "Running basic connectivity tests..."
    
    # Test Kafka topic creation
    if docker exec kafka-broker-1 kafka-topics --bootstrap-server kafka1:9092 --create --topic test-topic --partitions 1 --replication-factor 1 --if-not-exists > /dev/null 2>&1; then
        log_success "Kafka topic creation test passed"
        docker exec kafka-broker-1 kafka-topics --bootstrap-server kafka1:9092 --delete --topic test-topic > /dev/null 2>&1 || true
    else
        log_warning "Kafka topic creation test failed"
    fi
    
    # Test Schema Registry
    if curl -s http://localhost:8081/subjects > /dev/null; then
        log_success "Schema Registry connectivity test passed"
    else
        log_warning "Schema Registry connectivity test failed"
    fi
    
    # Test MinIO
    if curl -s http://localhost:9000/minio/health/live > /dev/null; then
        log_success "MinIO health test passed"
    else
        log_warning "MinIO health test failed"
    fi
}

# Main execution
main() {
    echo ""
    echo "=================================================="
    echo "IoT Data Pipeline Startup Script"
    echo "=================================================="
    echo ""
    
    # Pre-flight checks
    check_docker
    setup_directories
    check_required_jars
    
    # Cleanup and start services
    cleanup_existing
    
    log "Starting IoT Data Pipeline services..."
    echo ""
    
    # Start services in dependency order
    start_core_services
    echo ""
    
    start_flink_services
    echo ""
    
    start_application_services
    echo ""
    
    start_streaming_job
    echo ""
    
    # Show status and run tests
    show_service_status
    echo ""
    
    run_basic_tests
    echo ""
    
    show_logs
    echo ""
    
    log_success "IoT Data Pipeline startup complete!"
    echo ""
    echo "=================================================="
    echo "Next Steps:"
    echo "1. Start your ESP32 gateway to send RuuviTag data"
    echo "2. Monitor the pipeline using the web UIs"
    echo "3. Check Iceberg tables in MinIO for stored data"
    echo "=================================================="
    echo ""
    
    # Ask if user wants to monitor logs
    read -p "Would you like to monitor the streaming job logs? (y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd "$PROJECT_ROOT/docker"
        docker-compose logs -f flink-streaming-job
    fi
}

# Handle script interruption
trap 'log "Script interrupted. Services may still be running."; exit 1' INT TERM

# Run main function
main "$@"