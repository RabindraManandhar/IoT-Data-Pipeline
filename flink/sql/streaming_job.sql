-- Main streaming job: Kafka to Iceberg
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
    -- Partition fields for optimal storage
    SUBSTRING(device_id, 1, 8) as partition_device,
    EXTRACT(YEAR FROM event_time) as partition_year,
    EXTRACT(MONTH FROM event_time) as partition_month,
    EXTRACT(DAY FROM event_time) as partition_day,
    EXTRACT(HOUR FROM event_time) as partition_hour
FROM kafka_iot_source;

-- Aggregation job: Hourly statistics
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