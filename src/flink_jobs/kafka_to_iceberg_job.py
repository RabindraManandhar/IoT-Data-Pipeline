"""
Alternative PyFlink Streaming Job: Kafka to Iceberg ETL (Cluster Mode)
This version connects to the existing Flink cluster instead of running standalone
"""

import os
import json
import time
from datetime import datetime, timezone

from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings
from pyflink.common import Configuration

from src.utils.logger import log
from src.config.config import settings

class KafkaToIcebergJobCluster:
    """
    PyFlink streaming job that connects to existing Flink cluster
    """
    
    def __init__(self):
        """Initialize the streaming job for cluster mode"""
        self.env = None
        self.table_env = None
        self.job_client = None
        self._running = False
        
        # Initialize components
        self._setup_cluster_environment()
        
    def _setup_cluster_environment(self):
        """Setup Flink environment to connect to existing cluster"""
        try:
            # Create configuration for cluster connection
            config = Configuration()
            
            # Set JobManager address (from docker-compose)
            config.set_string("jobmanager.rpc.address", "flink-jobmanager")
            config.set_string("jobmanager.rpc.port", "6123")
            
            # Create remote execution environment
            self.env = StreamExecutionEnvironment.create_remote_environment(
                "flink-jobmanager", 6123, config=config
            )
            
            # Configure parallelism
            self.env.set_parallelism(2)
            
            # Create table environment
            settings_builder = EnvironmentSettings.new_instance().in_streaming_mode()
            table_settings = settings_builder.build()
            self.table_env = StreamTableEnvironment.create(self.env, table_settings)
            
            log.info("Flink cluster environment configured successfully")
            
        except Exception as e:
            log.error(f"Error setting up Flink cluster environment: {str(e)}")
            # Fall back to local environment if cluster connection fails
            log.info("Falling back to local execution environment")
            self._setup_local_environment()
    
    def _setup_local_environment(self):
        """Fallback: Setup local Flink environment"""
        try:
            self.env = StreamExecutionEnvironment.get_execution_environment()
            self.env.set_parallelism(2)
            
            settings_builder = EnvironmentSettings.new_instance().in_streaming_mode()
            table_settings = settings_builder.build()
            self.table_env = StreamTableEnvironment.create(self.env, table_settings)
            
            log.info("Local Flink environment configured as fallback")
            
        except Exception as e:
            log.error(f"Error setting up local Flink environment: {str(e)}")
            raise
    
    def _create_kafka_source_table(self):
        """Create Kafka source table using SQL DDL"""
        try:
            kafka_ddl = f"""
            CREATE TABLE kafka_source (
                device_id STRING,
                device_type STRING,
                timestamp_str STRING,
                value DOUBLE,
                unit STRING,
                location ROW<
                    latitude DOUBLE,
                    longitude DOUBLE,
                    building STRING,
                    floor INT,
                    zone STRING,
                    room STRING
                >,
                battery_level DOUBLE,
                signal_strength DOUBLE,
                is_anomaly BOOLEAN,
                firmware_version STRING,
                metadata MAP<STRING, STRING>,
                status STRING,
                tags ARRAY<STRING>,
                maintenance_date STRING,
                proc_time AS PROCTIME()
            ) WITH (
                'connector' = 'kafka',
                'topic' = '{settings.kafka.topic_name}',
                'properties.bootstrap.servers' = '{settings.kafka.bootstrap_servers}',
                'properties.group.id' = 'flink-iceberg-consumer',
                'scan.startup.mode' = 'latest-offset',
                'format' = 'json'
            )
            """
            
            self.table_env.execute_sql(kafka_ddl)
            log.info("Kafka source table created successfully")
            
        except Exception as e:
            log.error(f"Error creating Kafka source table: {str(e)}")
            raise
    
    def _create_iceberg_sink_table(self):
        """Create Iceberg sink table using SQL DDL"""
        try:
            # For simplicity, create a single Iceberg table
            iceberg_ddl = f"""
            CREATE TABLE iceberg_sink (
                device_id STRING,
                device_type STRING,
                event_time TIMESTAMP(3),
                value DOUBLE,
                unit STRING,
                location ROW<
                    latitude DOUBLE,
                    longitude DOUBLE,
                    building STRING,
                    floor INT,
                    zone STRING,
                    room STRING
                >,
                battery_level DOUBLE,
                signal_strength DOUBLE,
                is_anomaly BOOLEAN,
                firmware_version STRING,
                metadata MAP<STRING, STRING>,
                status STRING,
                tags ARRAY<STRING>,
                maintenance_date STRING
            ) WITH (
                'connector' = 'iceberg',
                'catalog-name' = 'iot_catalog',
                'uri' = '{os.getenv("ICEBERG_CATALOG_URI", "postgresql://iceberg:iceberg@postgres:5432/iceberg_catalog")}',
                'warehouse' = '{os.getenv("ICEBERG_WAREHOUSE_PATH", "s3a://iceberg-warehouse/")}',
                'database-name' = 'iot_data',
                'table-name' = 'sensor_readings'
            )
            """
            
            self.table_env.execute_sql(iceberg_ddl)
            log.info("Iceberg sink table created successfully")
            
        except Exception as e:
            log.error(f"Error creating Iceberg sink table: {str(e)}")
            raise
    
    def _create_processing_pipeline(self):
        """Create the main data processing pipeline using SQL"""
        try:
            # Create source and sink tables
            self._create_kafka_source_table()
            self._create_iceberg_sink_table()
            
            # Create the processing query
            processing_query = """
            INSERT INTO iceberg_sink
            SELECT 
                device_id,
                device_type,
                CAST(timestamp_str AS TIMESTAMP(3)) as event_time,
                value,
                unit,
                location,
                battery_level,
                signal_strength,
                is_anomaly,
                firmware_version,
                metadata,
                status,
                tags,
                maintenance_date
            FROM kafka_source
            """
            
            # Execute the streaming query
            self.job_client = self.table_env.execute_sql(processing_query)
            log.info("Processing pipeline created and started successfully")
            
        except Exception as e:
            log.error(f"Error creating processing pipeline: {str(e)}")
            raise
    
    def start(self):
        """Start the streaming job"""
        try:
            log.info("Starting Kafka to Iceberg streaming job (cluster mode)...")
            
            # Create processing pipeline
            self._create_processing_pipeline()
            self._running = True
            
            log.info("Streaming job started successfully")
            
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
        return self._running and self.job_client is not None