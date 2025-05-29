"""
PyFlink Job for Kafka to Iceberg ETL
This job is submitted to the Flink cluster via REST API
"""

import os
import json
from datetime import datetime
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings
from pyflink.common import Configuration

def create_kafka_source_ddl():
    """Create Kafka source table DDL"""
    return """
    CREATE TABLE kafka_iot_source (
        device_id STRING,
        device_type STRING,
        timestamp STRING,
        value DOUBLE,
        unit STRING,
        location ROW
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
        event_time AS TO_TIMESTAMP(timestamp),
        WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
    ) WITH (
        'connector' = 'kafka',
        'topic' = 'iot-sensor-data',
        'properties.bootstrap.servers' = 'kafka1:9092,kafka2:9092,kafka3:9092',
        'properties.group.id' = 'flink-iceberg-consumer',
        'scan.startup.mode' = 'latest-offset',
        'format' = 'avro-confluent',
        'avro-confluent.schema-registry.url' = 'http://schema-registry:8081'
    )
    """

def create_iceberg_sink_ddl():
    """Create Iceberg sink table DDL"""
    return """
    CREATE TABLE iceberg_iot_sink (
        device_id STRING,
        device_type STRING,
        event_time TIMESTAMP(3),
        processing_time TIMESTAMP(3),
        value DOUBLE,
        unit STRING,
        location ROW
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
        partition_device STRING,
        partition_year INT,
        partition_month INT,
        partition_day INT,
        partition_hour INT
    ) PARTITIONED BY (partition_device, partition_year, partition_month, partition_day)
    WITH (
        'connector' = 'iceberg',
        'catalog-name' = 'iot_catalog',
        'catalog-type' = 'rest',
        'uri' = 'http://iceberg-rest:8181',
        'warehouse' = 's3a://iceberg-warehouse/',
        'catalog-impl' = 'org.apache.iceberg.rest.RESTCatalog',
        'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
        's3.endpoint' = 'http://minio:9000',
        's3.access-key-id' = 'user',
        's3.secret-access-key' = 'password',
        's3.path-style-access' = 'true',
        'database-name' = 'iot_data',
        'table-name' = 'sensor_readings',
        'format-version' = '2'
    )
    """

def create_iceberg_iot_aggregate_hourly():
    """Create aggregated results table for analytics"""
    return """
    CREATE TABLE iceberg_iot_hourly (
        device_id STRING,
        device_type STRING,
        hour_window TIMESTAMP(3),
        avg_value DOUBLE,
        min_value DOUBLE,
        max_value DOUBLE,
        reading_count BIGINT,
        anomaly_count BIGINT,
        battery_level DOUBLE,
        partition_device STRING,
        partition_year INT,
        partition_month INT,
        partition_day INT,
        partition_hour INT
    ) PARTITIONED BY (partition_device, partition_year, partition_month, partition_day)
    WITH (
        'connector' = 'iceberg',
        'catalog-name' = 'iot_catalog',
        'catalog-type' = 'rest',
        'uri' = 'http://iceberg-rest:8181',
        'warehouse' = 's3a://iceberg-warehouse/',
        'catalog-impl' = 'org.apache.iceberg.rest.RESTCatalog',
        'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
        's3.endpoint' = 'http://minio:9000',
        's3.access-key-id' = 'user',
        's3.secret-access-key' = 'password',
        's3.path-style-access' = 'true',
        'database-name' = 'iot_data',
        'table-name' = 'sensor_readings_hourly',
        'format-version' = '2'
    );
    """

def create_streaming_job_sql():
    """Main streaming job: Kafka to Iceberg"""
    return """
    INSERT INTO iceberg_iot_sink
    SELECT 
        device_id,
        device_type,
        event_time,
        PROCTIME() as processing_time,
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
        maintenance_date,
        SUBSTRING(device_id, 1, 8) as partition_device,
        EXTRACT(YEAR FROM event_time) as partition_year,
        EXTRACT(MONTH FROM event_time) as partition_month,
        EXTRACT(DAY FROM event_time) as partition_day,
        EXTRACT(HOUR FROM event_time) as partition_hour
    FROM kafka_iot_source
    """

def create_aggregate_job_hourly():
    """Aggregation job: Hourly statistics"""
    return """
    INSERT INTO iceberg_iot_hourly
    SELECT 
        device_id,
        device_type,
        TUMBLE_START(event_time, INTERVAL '1' HOUR) as hour_window,
        AVG(value) as avg_value,
        MIN(value) as min_value,
        MAX(value) as max_value,
        COUNT(*) as reading_count,
        SUM(CASE WHEN is_anomaly THEN 1 ELSE 0 END) as anomaly_count,
        LAST_VALUE(battery_level) as battery_level,
        SUBSTRING(device_id, 1, 8) as partition_device,
        EXTRACT(YEAR FROM TUMBLE_START(event_time, INTERVAL '1' HOUR)) as partition_year,
        EXTRACT(MONTH FROM TUMBLE_START(event_time, INTERVAL '1' HOUR)) as partition_month,
        EXTRACT(DAY FROM TUMBLE_START(event_time, INTERVAL '1' HOUR)) as partition_day,
        EXTRACT(HOUR FROM TUMBLE_START(event_time, INTERVAL '1' HOUR)) as partition_hour
    FROM kafka_iot_source
    WHERE value IS NOT NULL
    GROUP BY 
        device_id,
        device_type,
        TUMBLE(event_time, INTERVAL '1' HOUR);
    """

def main():
    """Main function for the PyFlink job"""
    # Create execution environment
    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(2)
    
    # Create table environment
    settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    table_env = StreamTableEnvironment.create(env, settings)
    
    # Add required JARs
    jars = [
        "file:///opt/flink/lib/custom/flink-connector-kafka-3.2.0-1.19.jar",
        "file:///opt/flink/lib/custom/flink-sql-connector-kafka-3.2.0-1.19.jar",
        "file:///opt/flink/lib/custom/flink-avro-1.19.1.jar",
        "file:///opt/flink/lib/custom/iceberg-flink-runtime-1.19-1.9.0.jar",
        "file:///opt/flink/lib/custom/hadoop-aws-3.3.6.jar",
        "file:///opt/flink/lib/custom/aws-java-sdk-bundle-1.12.728.jar"
    ]
    
    for jar in jars:
        table_env.get_config().get_configuration().set_string("pipeline.jars", jar)
    
    print("Creating Kafka source table...")
    table_env.execute_sql(create_kafka_source_ddl())
    
    print("Creating Iceberg sink table...")
    table_env.execute_sql(create_iceberg_sink_ddl())
    
    print("Starting streaming job from kafka to iceberg...")
    table_env.execute_sql(create_streaming_job_sql())

    print("Starting hourly aggregation job...")
    table_env.execute_sql(create_aggregate_job_hourly())
    
    print("Job submitted successfully!")

if __name__ == "__main__":
    main()