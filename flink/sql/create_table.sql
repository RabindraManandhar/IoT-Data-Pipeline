-- Create Kafka Source Table
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
);

-- Create Iceberg Sink Table
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
    -- Partition fields
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
);

-- Create aggregated results table for analytics
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