#!/bin/bash
# MQTT Broker Troubleshooting Script
# Run this if you're having issues with MQTT broker startup

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

echo "=================================================="
echo "MQTT Broker Troubleshooting Script"
echo "=================================================="
echo ""

# Check if Docker is running
log "Checking Docker..."
if ! docker info &> /dev/null; then
    log_error "Docker is not running. Please start Docker first."
    exit 1
fi
log_success "Docker is running"

# Check if port 1883 is in use
log "Checking if port 1883 is in use..."
if command -v lsof >/dev/null 2>&1; then
    if lsof -i :1883 >/dev/null 2>&1; then
        log_warning "Port 1883 is already in use:"
        lsof -i :1883
        echo ""
        log "If you have a local mosquitto service running, stop it with:"
        log "sudo systemctl stop mosquitto"
        log "sudo systemctl disable mosquitto"
    else
        log_success "Port 1883 is available"
    fi
elif command -v netstat >/dev/null 2>&1; then
    if netstat -an | grep -q ":1883"; then
        log_warning "Port 1883 appears to be in use:"
        netstat -an | grep ":1883"
    else
        log_success "Port 1883 is available"
    fi
else
    log_warning "Cannot check port usage (lsof and netstat not available)"
fi

echo ""

# Check mosquitto container status
log "Checking mosquitto container status..."
if docker ps --filter "name=mosquitto" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q mosquitto; then
    log_success "Mosquitto container is running:"
    docker ps --filter "name=mosquitto" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
else
    log_warning "Mosquitto container is not running"
    
    # Check if container exists but is stopped
    if docker ps -a --filter "name=mosquitto" --format "table {{.Names}}\t{{.Status}}" | grep -q mosquitto; then
        log "Found stopped mosquitto container:"
        docker ps -a --filter "name=mosquitto" --format "table {{.Names}}\t{{.Status}}"
        
        log "Attempting to start mosquitto container..."
        if docker start mosquitto; then
            log_success "Started mosquitto container"
            sleep 5
        else
            log_error "Failed to start mosquitto container"
        fi
    else
        log "No mosquitto container found. Run docker-compose up -d mosquitto first."
    fi
fi

echo ""

# Check mosquitto logs
log "Checking mosquitto logs (last 20 lines)..."
if docker ps --filter "name=mosquitto" --quiet | grep -q .; then
    docker logs --tail 20 mosquitto
else
    log_warning "Cannot show logs - mosquitto container is not running"
fi

echo ""

# Test MQTT connection
log "Testing MQTT broker connectivity..."

# Method 1: Test with docker exec mosquitto_pub
if docker ps --filter "name=mosquitto" --quiet | grep -q .; then
    log "Testing with mosquitto_pub..."
    if docker exec mosquitto mosquitto_pub -h localhost -t "test/topic" -m "test message" 2>/dev/null; then
        log_success "mosquitto_pub test successful"
    else
        log_warning "mosquitto_pub test failed"
    fi
    
    # Method 2: Test with mosquitto_sub (with timeout)
    log "Testing with mosquitto_sub (5 second timeout)..."
    if timeout 5 docker exec mosquitto mosquitto_sub -h localhost -t "test/topic" -C 1 >/dev/null 2>&1 &
       docker exec mosquitto mosquitto_pub -h localhost -t "test/topic" -m "test" >/dev/null 2>&1; then
        log_success "mosquitto_sub/pub test successful"
    else
        log_warning "mosquitto_sub/pub test failed or timed out"
    fi
else
    log_warning "Cannot test MQTT - container not running"
fi

echo ""

# Check network connectivity
log "Checking Docker network connectivity..."
if docker network ls | grep -q "docker_kafka-net"; then
    log_success "kafka-net network exists"
    
    # Check if mosquitto is connected to the network
    if docker network inspect docker_kafka-net | grep -q "mosquitto"; then
        log_success "Mosquitto is connected to kafka-net network"
    else
        log_warning "Mosquitto is not connected to kafka-net network"
        log "Try: docker network connect docker_kafka-net mosquitto"
    fi
else
    log_warning "kafka-net network does not exist"
    log "Run docker-compose up to create the network"
fi

echo ""

# Provide troubleshooting recommendations
echo "=== Troubleshooting Recommendations ==="
echo ""

if ! docker ps --filter "name=mosquitto" --quiet | grep -q .; then
    echo "1. Start the mosquitto container:"
    echo "   cd docker && docker-compose up -d mosquitto"
    echo ""
fi

echo "2. If port 1883 is in use by local mosquitto service:"
echo "   sudo systemctl stop mosquitto"
echo "   sudo systemctl disable mosquitto"
echo ""

echo "3. If container keeps failing, check configuration:"
echo "   docker-compose logs mosquitto"
echo ""

echo "4. Reset everything and start fresh:"
echo "   cd docker && docker-compose down -v"
echo "   docker-compose up -d mosquitto"
echo ""

echo "5. Test manually with MQTT client:"
echo "   # Install mosquitto-clients locally"
echo "   mosquitto_pub -h localhost -p 1883 -t test -m 'hello'"
echo "   mosquitto_sub -h localhost -p 1883 -t test"
echo ""

echo "6. Check firewall/security software:"
echo "   Some security software blocks Docker port binding"
echo ""

echo "7. For M1/M2 Macs, ensure Docker Desktop is using Apple Silicon images"
echo ""

echo "=== Current Docker Compose Status ==="
if [ -f "docker/docker-compose.yml" ]; then
    cd docker
    docker-compose ps mosquitto
else
    log_warning "docker-compose.yml not found. Run from project root directory."
fi

echo ""
echo "If issues persist, please share the output of this script when asking for help."