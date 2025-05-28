#!/usr/bin/env python3
"""
PyFlink Streaming Job Runner for IoT Data Pipeline
Streams data from Kafka to Iceberg tables with automatic schema evolution
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
    from confluent_kafka.admin import AdminClient
    
    backoff = initial_backoff
    dependencies = {
        'Schema Registry': f"{settings.schema_registry.url}/subjects",
        'Kafka': settings.kafka.bootstrap_servers,
        'MinIO': f"{os.getenv('MINIO_ENDPOINT', 'http://minio:9000')}/minio/health/live",
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
    log.info(f"Kafka Bootstrap Servers: {settings.kafka.bootstrap_servers}")
    log.info(f"Kafka Topic: {settings.kafka.topic_name}")
    log.info(f"Schema Registry URL: {settings.schema_registry.url}")
    log.info(f"Environment: {settings.environment}")

def setup_environment():
    """Setup environment variables for PyFlink"""
    try:
        # Set required environment variables
        os.environ['FLINK_HOME'] = '/opt/flink'
        os.environ['JAVA_HOME'] = '/usr/lib/jvm/temurin-11-jdk-amd64'
        
        # Add JAR files to classpath if they exist
        jar_files = [
            '/app/jars/flink-connector-kafka-3.2.0-1.19.jar',
            '/app/jars/flink-sql-connector-kafka-3.2.0-1.19.jar',
            '/app/jars/flink-avro-1.19.1.jar',
            '/app/jars/hadoop-aws-3.3.6.jar',
            '/app/jars/aws-java-sdk-bundle-1.12.728.jar',
        ]
        
        existing_jars = [jar for jar in jar_files if os.path.exists(jar)]
        if existing_jars:
            classpath = ':'.join(existing_jars)
            current_classpath = os.environ.get('CLASSPATH', '')
            os.environ['CLASSPATH'] = f"{current_classpath}:{classpath}" if current_classpath else classpath
            log.info(f"Added {len(existing_jars)} JAR files to classpath")
        
        log.info("Environment setup completed")
        
    except Exception as e:
        log.error(f"Error setting up environment: {str(e)}")
        raise

def create_job_instance():
    """Create the appropriate job instance based on available options"""
    global job_instance
    
    try:
        # Try to import and use the main streaming job
        from src.flink_jobs.kafka_to_iceberg_job import KafkaToIcebergJob
        job_instance = KafkaToIcebergJob()
        log.info("Created KafkaToIcebergJob instance")
        return job_instance
        
    except Exception as e:
        log.warning(f"Failed to create main job instance: {str(e)}")
        log.info("Trying alternative simple processing approach...")
        
        try:
            # Fallback to a simpler approach that just processes data
            job_instance = SimpleKafkaProcessor()
            log.info("Created SimpleKafkaProcessor instance as fallback")
            return job_instance
            
        except Exception as e2:
            log.error(f"Failed to create fallback job instance: {str(e2)}")
            raise

class SimpleKafkaProcessor:
    """
    Simple Kafka processor as fallback when PyFlink setup fails
    """
    
    def __init__(self):
        self._running = False
        log.info("Initialized SimpleKafkaProcessor")
    
    def start(self):
        """Start the simple processor"""
        try:
            from confluent_kafka import Consumer
            from src.utils.schema_registry import schema_registry
            
            # Create Kafka consumer
            consumer_config = settings.consumer.get_config(
                group_id="simple-flink-processor",
                auto_offset_reset="latest"
            )
            
            consumer = Consumer(consumer_config)
            consumer.subscribe([settings.kafka.topic_name])
            
            self._running = True
            log.info("Simple Kafka processor started")
            
            # Simple processing loop
            while self._running:
                msg = consumer.poll(timeout=1.0)
                
                if msg is None:
                    continue
                    
                if msg.error():
                    log.error(f"Consumer error: {msg.error()}")
                    continue
                
                try:
                    # Deserialize message
                    data = schema_registry.deserialize_sensor_reading(
                        msg.value(), settings.kafka.topic_name
                    )
                    
                    # Simple processing - just log for now
                    device_id = data.get('device_id', 'unknown')
                    device_type = data.get('device_type', 'unknown')
                    value = data.get('value', 'unknown')
                    
                    if self._running and (time.time() % 60 < 1):  # Log every minute
                        log.info(f"Processed: {device_id} ({device_type}) = {value}")
                    
                except Exception as e:
                    log.error(f"Error processing message: {str(e)}")
                
                time.sleep(0.1)  # Small delay to prevent CPU spinning
            
            consumer.close()
            log.info("Simple processor stopped")
            
        except Exception as e:
            log.error(f"Error in simple processor: {str(e)}")
            raise
    
    def stop(self):
        """Stop the processor"""
        self._running = False
        log.info("Stopping simple processor...")
    
    def is_running(self):
        """Check if running"""
        return self._running

def main():
    """Main function to run the PyFlink streaming job"""
    global job_instance
    
    # Setup signal handlers for graceful shutdown
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        log.info("Starting PyFlink IoT Data Streaming Job")
        log_configuration()
        
        # Setup environment
        setup_environment()
        
        # Wait for dependencies
        log.info("Waiting for dependencies to be ready...")
        if not wait_for_dependencies():
            log.error("Dependencies are not ready. Exiting.")
            sys.exit(1)
        
        # Create job instance
        log.info("Creating streaming job instance...")
        job_instance = create_job_instance()
        
        # Start the job
        log.info("Starting streaming job...")
        job_instance.start()
        
        # Keep the main thread alive
        log.info("Streaming job is running. Press Ctrl+C to stop.")
        while True:
            time.sleep(60)  # Check every minute
            if hasattr(job_instance, 'is_running') and not job_instance.is_running():
                log.warning("Job stopped unexpectedly")
                break
        
    except KeyboardInterrupt:
        log.info("Job interrupted by user")
    except Exception as e:
        log.error(f"Unexpected error in streaming job: {str(e)}")
        import traceback
        log.error(traceback.format_exc())
        sys.exit(1)
    finally:
        if job_instance:
            job_instance.stop()
        log.info("Streaming job shutdown complete")

if __name__ == "__main__":
    main()