"""
PyFlink Streaming Job: Kafka to Iceberg ETL
Streams IoT sensor data from Kafka to Iceberg tables with automatic schema evolution
"""

import os
import json
import time
from datetime import datetime, timezone
from typing import Dict, Any, Optional

from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings
from pyflink.table.types import DataTypes
from pyflink.table.schema import Schema
from pyflink.common import Types, WatermarkStrategy, Time
from pyflink.datastream.connectors.kafka import KafkaSource, KafkaOffsetsInitializer
from pyflink.common.serialization import SimpleStringSchema
from pyflink.datastream.functions import MapFunction, ProcessFunction
from pyflink.datastream.state import ValueStateDescriptor
from pyflink.common.typeinfo import Types as FlinkTypes

from src.utils.logger import log
from src.config.config import settings
from src.iceberg.iceberg_manager import IcebergManager

class IoTDataProcessor(ProcessFunction):
    """
    Process function to handle IoT sensor data and prepare for Iceberg
    """
    
    def __init__(self):
        self.iceberg_manager = None
        self.last_schema_check = None
        
    def open(self, runtime_context):
        """Initialize the processor"""
        try:
            self.iceberg_manager = IcebergManager()
            self.last_schema_check = ValueStateDescriptor(
                "last_schema_check", FlinkTypes.LONG()
            )
            log.info("IoTDataProcessor initialized successfully")
        except Exception as e:
            log.error(f"Error initializing IoTDataProcessor: {str(e)}")
            raise
    
    def process_element(self, value, ctx, out):
        """
        Process each IoT sensor reading
        
        Args:
            value: JSON string containing IoT sensor data
            ctx: Processing context
            out: Output collector
        """
        try:
            # Parse JSON data
            data = json.loads(value)
            
            # Add processing metadata
            processing_time = datetime.now(timezone.utc).isoformat()
            data['processing_time'] = processing_time
            data['event_time'] = data.get('timestamp', processing_time)
            
            # Extract partition keys
            device_id = data.get('device_id', 'unknown')
            event_time = datetime.fromisoformat(data['event_time'].replace('Z', '+00:00'))
            
            # Add partition columns for Iceberg
            data['partition_device'] = device_id
            data['partition_year'] = event_time.year
            data['partition_month'] = event_time.month
            data['partition_day'] = event_time.day
            data['partition_hour'] = event_time.hour
            
            # Emit processed data
            out.collect(json.dumps(data))
            
        except Exception as e:
            log.error(f"Error processing IoT data: {str(e)}")
            # Emit to dead letter queue or skip
            pass

class AvroDeserializer(MapFunction):
    """
    Custom deserializer for Avro data from Kafka
    """
    
    def __init__(self):
        self.schema_registry_client = None
        
    def open(self, runtime_context):
        """Initialize the deserializer"""
        try:
            from src.utils.schema_registry import schema_registry
            self.schema_registry_client = schema_registry
            log.info("Avro deserializer initialized")
        except Exception as e:
            log.error(f"Error initializing Avro deserializer: {str(e)}")
            raise
    
    def map(self, value):
        """
        Deserialize Avro-encoded data
        
        Args:
            value: Avro-encoded bytes
            
        Returns:
            JSON string of deserialized data
        """
        try:
            # Deserialize Avro data
            deserialized_data = self.schema_registry_client.deserialize_sensor_reading(
                value, settings.kafka.topic_name
            )
            return json.dumps(deserialized_data)
            
        except Exception as e:
            log.error(f"Error deserializing Avro data: {str(e)}")
            return "{}"  # Return empty JSON on error

class KafkaToIcebergJob:
    """
    Main PyFlink streaming job class for Kafka to Iceberg ETL
    """
    
    def __init__(self):
        """Initialize the streaming job"""
        self.env = None
        self.table_env = None
        self.job_client = None
        self.iceberg_manager = None
        self._running = False
        
        # Initialize components
        self._setup_environment()
        self._setup_iceberg()
        
    def _setup_environment(self):
        """Setup Flink execution environment"""
        try:
            # Create stream execution environment
            self.env = StreamExecutionEnvironment.get_execution_environment()
            
            # Configure parallelism and checkpointing
            self.env.set_parallelism(2)  # Adjust based on TaskManager configuration
            self.env.enable_checkpointing(60000)  # Checkpoint every minute
            
            # Configure restart strategy
            self.env.get_checkpoint_config().set_checkpoint_timeout(300000)  # 5 minutes
            self.env.get_checkpoint_config().set_max_concurrent_checkpoints(1)
            
            # Create table environment
            settings_builder = EnvironmentSettings.new_instance().in_streaming_mode()
            table_settings = settings_builder.build()
            self.table_env = StreamTableEnvironment.create(self.env, table_settings)
            
            # Add required JARs to table environment
            self._configure_connectors()
            
            log.info("Flink environment configured successfully")
            
        except Exception as e:
            log.error(f"Error setting up Flink environment: {str(e)}")
            raise
    
    def _configure_connectors(self):
        """Configure Flink connectors and JARs"""
        try:
            # Add Kafka connector
            self.table_env.get_config().get_configuration().set_string(
                "pipeline.jars",
                "file:///app/jars/flink-connector-kafka-3.2.0-1.19.jar;"
                "file:///app/jars/flink-sql-connector-kafka-3.2.0-1.19.jar;"
                "file:///app/jars/flink-avro-1.19.1.jar"
            )
            
            # Configure Hadoop/S3 for MinIO
            config = self.table_env.get_config().get_configuration()
            config.set_string("fs.s3a.endpoint", os.getenv("MINIO_ENDPOINT", "http://minio:9000"))
            config.set_string("fs.s3a.access.key", os.getenv("MINIO_ACCESS_KEY", "minioadmin"))
            config.set_string("fs.s3a.secret.key", os.getenv("MINIO_SECRET_KEY", "minioadmin"))
            config.set_string("fs.s3a.path.style.access", "true")
            config.set_string("fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
            
            log.info("Flink connectors configured successfully")
            
        except Exception as e:
            log.error(f"Error configuring connectors: {str(e)}")
            raise
    
    def _setup_iceberg(self):
        """Setup Iceberg manager"""
        try:
            self.iceberg_manager = IcebergManager()
            log.info("Iceberg manager initialized successfully")
        except Exception as e:
            log.error(f"Error setting up Iceberg: {str(e)}")
            raise
    
    def _create_kafka_source(self) -> KafkaSource:
        """Create and configure Kafka source"""
        try:
            kafka_source = (
                KafkaSource.builder()
                .set_bootstrap_servers(settings.kafka.bootstrap_servers)
                .set_topics([settings.kafka.topic_name])
                .set_group_id("flink-iceberg-consumer")
                .set_starting_offsets(KafkaOffsetsInitializer.latest())
                .set_value_only_deserializer(SimpleStringSchema())
                .build()
            )
            
            log.info(f"Kafka source configured for topic: {settings.kafka.topic_name}")
            return kafka_source
            
        except Exception as e:
            log.error(f"Error creating Kafka source: {str(e)}")
            raise
    
    def _create_processing_pipeline(self):
        """Create the main data processing pipeline"""
        try:
            # Create Kafka source
            kafka_source = self._create_kafka_source()
            
            # Create data stream from Kafka
            kafka_stream = self.env.from_source(
                kafka_source,
                WatermarkStrategy.no_watermarks(),
                "kafka-source"
            )
            
            # Deserialize Avro data (if needed) and process
            processed_stream = (
                kafka_stream
                .map(AvroDeserializer(), output_type=FlinkTypes.STRING())
                .name("avro-deserializer")
                .process(IoTDataProcessor(), output_type=FlinkTypes.STRING())
                .name("iot-data-processor")
            )
            
            # Convert to table for easier handling
            self.table_env.create_temporary_view(
                "iot_data_stream",
                processed_stream,
                Schema.new_builder()
                .column("data", DataTypes.STRING())
                .build()
            )
            
            # Create sink to Iceberg via custom sink function
            processed_stream.add_sink(IcebergSinkFunction()).name("iceberg-sink")
            
            log.info("Processing pipeline created successfully")
            
        except Exception as e:
            log.error(f"Error creating processing pipeline: {str(e)}")
            raise
    
    def start(self):
        """Start the streaming job"""
        try:
            log.info("Starting Kafka to Iceberg streaming job...")
            
            # Create processing pipeline
            self._create_processing_pipeline()
            
            # Execute the job
            self.job_client = self.env.execute_async("kafka-to-iceberg-job")
            self._running = True
            
            log.info("Streaming job started successfully")
            log.info(f"Job ID: {self.job_client.get_job_id()}")
            
        except Exception as e:
            log.error(f"Error starting streaming job: {str(e)}")
            raise
    
    def stop(self):
        """Stop the streaming job"""
        try:
            if self.job_client and self._running:
                log.info("Stopping streaming job...")
                self.job_client.cancel()
                self._running = False
                log.info("Streaming job stopped successfully")
        except Exception as e:
            log.error(f"Error stopping streaming job: {str(e)}")
    
    def is_running(self) -> bool:
        """Check if the job is running"""
        if not self.job_client or not self._running:
            return False
        
        try:
            status = self.job_client.get_job_status()
            return status.name in ['RUNNING', 'CREATED', 'INITIALIZING']
        except:
            return False

class IcebergSinkFunction:
    """
    Custom sink function to write data to Iceberg tables
    """
    
    def __init__(self):
        self.iceberg_manager = None
        self.batch_buffer = []
        self.batch_size = 1000
        self.last_flush = time.time()
        self.flush_interval = 30  # seconds
        
    def open(self, runtime_context):
        """Initialize the sink"""
        try:
            self.iceberg_manager = IcebergManager()
            log.info("Iceberg sink function initialized")
        except Exception as e:
            log.error(f"Error initializing Iceberg sink: {str(e)}")
            raise
    
    def invoke(self, value, context):
        """
        Write data to Iceberg
        
        Args:
            value: JSON string containing processed IoT data
            context: Sink context
        """
        try:
            # Parse the JSON data
            data = json.loads(value)
            
            # Add to batch buffer
            self.batch_buffer.append(data)
            
            # Check if we should flush
            current_time = time.time()
            should_flush = (
                len(self.batch_buffer) >= self.batch_size or
                (current_time - self.last_flush) >= self.flush_interval
            )
            
            if should_flush:
                self._flush_batch()
                
        except Exception as e:
            log.error(f"Error in Iceberg sink: {str(e)}")
    
    def _flush_batch(self):
        """Flush the current batch to Iceberg"""
        if not self.batch_buffer:
            return
            
        try:
            # Group data by device type for different tables
            grouped_data = {}
            for record in self.batch_buffer:
                device_type = record.get('device_type', 'unknown')
                if device_type not in grouped_data:
                    grouped_data[device_type] = []
                grouped_data[device_type].append(record)
            
            # Write each group to its respective table
            for device_type, records in grouped_data.items():
                table_name = f"iot_{device_type.lower().replace(' ', '_').replace('-', '_')}"
                self.iceberg_manager.write_batch(table_name, records)
            
            log.info(f"Flushed {len(self.batch_buffer)} records to Iceberg across {len(grouped_data)} tables")
            
            # Clear buffer and update last flush time
            self.batch_buffer.clear()
            self.last_flush = time.time()
            
        except Exception as e:
            log.error(f"Error flushing batch to Iceberg: {str(e)}")
            # Don't clear buffer on error - retry on next flush
    
    def close(self):
        """Close the sink and flush remaining data"""
        if self.batch_buffer:
            self._flush_batch()
        log.info("Iceberg sink function closed")