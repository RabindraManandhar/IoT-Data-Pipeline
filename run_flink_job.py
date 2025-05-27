#!/usr/bin/env python3
"""
PyFlink Streaming Job Runner for IoT Data Pipeline
Streams data from Kafka to PyIceberg with automatic schema evolution
"""

import os
import sys
import time
import signal
from pathlib import Path

# Add source directory to Python path
sys.path.insert(0, '/app')

from src.utils.logger import log
from src.config.config import settings
from src.flink_jobs.kafka_to_iceberg_job import KafkaToIcebergJob

# Global job instance for graceful shutdown
job_instance = None

def signal_handler(sig, frame):
    """Handle termination signals for graceful shutdown"""
    global job_instance
    log.info(f"Caught signal {sig}. Stopping Flink job...")
    if job_instance:
        job_instance.stop()
    sys.exit(0)

def wait_for_dependencies(max_retries=60, initial_backoff=5):
    """
    Wait for all dependencies to be ready before starting the job
    
    Args:
        max_retries: Maximum number of retry attempts
        initial_backoff: Initial backoff time in seconds
    
    Returns:
        True if all dependencies are ready, False otherwise
    """
    import requests
    import psycopg2
    from confluent_kafka.admin import AdminClient
    
    backoff = initial_backoff
    dependencies = {
        'Flink JobManager': f"http://{os.getenv('FLINK_JOBMANAGER_HOST', 'flink-jobmanager')}:8081/overview",
        'Schema Registry': f"{settings.schema_registry.url}/subjects",
        'Kafka': settings.kafka.bootstrap_servers,
        'MinIO': f"{os.getenv('MINIO_ENDPOINT', 'http://minio:9000')}/minio/health/live",
        'PostgreSQL': os.getenv('ICEBERG_CATALOG_URI', 'postgresql://iceberg:iceberg@postgres:5432/iceberg_catalog')
    }
    
    for attempt in range(1, max_retries + 1):
        all_ready = True
        
        for service_name, endpoint in dependencies.items():
            try:
                if service_name == 'Kafka':
                    # Test Kafka connection
                    admin_client = AdminClient({'bootstrap.servers': endpoint})
                    metadata = admin_client.list_topics(timeout=10)
                    log.debug(f"Kafka is ready with {len(metadata.topics)} topics")
                    
                elif service_name == 'PostgreSQL':
                    # Test PostgreSQL connection
                    conn = psycopg2.connect(endpoint)
                    cur = conn.cursor()
                    cur.execute("SELECT version();")
                    cur.fetchone()
                    cur.close()
                    conn.close()
                    log.debug(f"PostgreSQL is ready")
                    
                else:
                    # Test HTTP endpoints
                    response = requests.get(endpoint, timeout=10)
                    response.raise_for_status()
                    log.debug(f"{service_name} is ready")
                    
            except Exception as e:
                log.warning(f"{service_name} not ready: {str(e)}")
                all_ready = False
                break
        
        if all_ready:
            log.info("All dependencies are ready!")
            return True
        
        if attempt < max_retries:
            log.info(f"Waiting {backoff} seconds before retry {attempt + 1}/{max_retries}...")
            time.sleep(backoff)
            backoff = min(backoff * 1.2, 30)  # Exponential backoff with cap
        else:
            log.error(f"Dependencies not ready after {max_retries} attempts")
            return False
    
    return False

def log_configuration():
    """Log the current configuration settings"""
    log.info("Flink Streaming Job Configuration:")
    log.info(f"Flink JobManager: {os.getenv('FLINK_JOBMANAGER_HOST', 'flink-jobmanager')}:{os.getenv('FLINK_JOBMANAGER_PORT', '6123')}")
    log.info(f"Kafka Bootstrap Servers: {settings.kafka.bootstrap_servers}")
    log.info(f"Kafka Topic: {settings.kafka.topic_name}")
    log.info(f"Schema Registry URL: {settings.schema_registry.url}")
    log.info(f"Iceberg Catalog URI: {os.getenv('ICEBERG_CATALOG_URI')}")
    log.info(f"Iceberg Warehouse Path: {os.getenv('ICEBERG_WAREHOUSE_PATH')}")
    log.info(f"MinIO Endpoint: {os.getenv('MINIO_ENDPOINT')}")
    log.info(f"Environment: {settings.environment}")

def setup_flink_environment():
    """Setup Flink environment and JARs"""
    try:
        # Set Flink configuration
        os.environ['FLINK_HOME'] = '/opt/flink'
        
        # Add required JARs to classpath
        jar_files = [
            '/app/jars/flink-connector-kafka-3.2.0-1.19.jar',
            '/app/jars/flink-connector-files-1.19.1.jar', 
            '/app/jars/flink-sql-connector-kafka-3.2.0-1.19.jar',
            '/app/jars/flink-avro-1.19.1.jar',
            '/app/jars/flink-parquet-1.19.1.jar',
            '/app/jars/hadoop-aws-3.3.6.jar',
            '/app/jars/aws-java-sdk-bundle-1.12.728.jar',
            '/app/jars/iceberg-flink-runtime-1.19-1.9.0.jar'
        ]
        
        # Check if JAR files exist
        existing_jars = []
        for jar_file in jar_files:
            if os.path.exists(jar_file):
                existing_jars.append(jar_file)
            else:
                log.warning(f"JAR file not found: {jar_file}")
        
        if existing_jars:
            classpath = ':'.join(existing_jars)
            os.environ['FLINK_CLASSPATH'] = classpath
            log.info(f"Added {len(existing_jars)} JAR files to Flink classpath")
        else:
            log.warning("No JAR files found - some functionality may be limited")
            
    except Exception as e:
        log.error(f"Error setting up Flink environment: {str(e)}")
        raise

def main():
    """Main function to run the PyFlink streaming job"""
    global job_instance
    
    # Setup signal handlers for graceful shutdown
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        log.info("Starting PyFlink IoT Data Streaming Job")
        log_configuration()
        
        # Setup Flink environment
        setup_flink_environment()
        
        # Wait for all dependencies to be ready
        log.info("Waiting for dependencies to be ready...")
        if not wait_for_dependencies():
            log.error("Dependencies are not ready. Exiting.")
            sys.exit(1)
        
        # Create and configure the streaming job
        log.info("Creating Kafka to Iceberg streaming job...")
        job_instance = KafkaToIcebergJob()
        
        # Start the job
        log.info("Starting streaming job...")
        job_instance.start()
        
        # Keep the main thread alive
        log.info("Streaming job is running. Press Ctrl+C to stop.")
        while True:
            time.sleep(60)  # Check every minute
            if not job_instance.is_running():
                log.warning("Job stopped unexpectedly")
                break
        
    except KeyboardInterrupt:
        log.info("Job interrupted by user")
    except Exception as e:
        log.error(f"Unexpected error in streaming job: {str(e)}")
        raise
    finally:
        if job_instance:
            job_instance.stop()
        log.info("Streaming job shutdown complete")

if __name__ == "__main__":
    main()