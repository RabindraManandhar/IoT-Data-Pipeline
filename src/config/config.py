import os
import yaml
from pydantic import Field, field_validator
from pydantic_settings import BaseSettings
from dotenv import load_dotenv
from typing import Dict, List, Any, Optional

# Load environment variables from .env file if it exists
load_dotenv()

def load_yaml_config():
    try:
        config_path = os.getenv('CONFIG_FILE_PATH', 'config.yaml')
        if os.path.isdir(config_path):
            print(f"Expected config file but found directory at {config_path}")
            return {}
            
        with open(config_path, 'r') as file:
            return yaml.safe_load(file)

    except Exception as e:
        print(f"Error loading configuration from {config_path}: {str(e)}")
        print("Falling back to environment variables and default values")
        return {}

# Load configuration from YAML file
yaml_config = load_yaml_config()

class KafkaSettings(BaseSettings):
    """
    Kafka configuration settings for a multi-broker environment.
    
    Attributes:
        bootstrap_servers: Comma-separated list of Kafka broker addresses
        topic_name: Name of the Kafka topic for IoT data
        consumer_group_id: ID of the consumer group for load balancing
        auto_offset_reset: Strategy for consuming messages ('earliest' or 'latest')
        replication_factor: Number of replicas for __consumer_offsets topic, which stores Kafka consumer group offsets (used for committing and recovering offset positions).
        partitions: Number of partitions for the topics
    """
    # Support comma-delimited string of brokers or use default if not provided
    bootstrap_servers: str = Field(
        default_factory=lambda: yaml_config.get('kafka', {}).get('bootstrap_servers') or 
                        os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka1:9092,kafka2:9092,kafka3:9092")
    )
    
    # Topic configuration
    topic_name: str = Field(
        default_factory=lambda: yaml_config.get('kafka', {}).get('topic_name') or 
                        os.getenv("KAFKA_TOPIC_NAME", "iot-sensor-data")
    )
    
    consumer_group_id: str = Field(
        default_factory=lambda: yaml_config.get('kafka', {}).get('consumer_group_id') or 
                        os.getenv("KAFKA_CONSUMER_GROUP_ID", "iot-data-consumer")
    )
    
    auto_offset_reset: str = Field(
        default_factory=lambda: yaml_config.get('kafka', {}).get('auto_offset_reset') or 
                        os.getenv("KAFKA_AUTO_OFFSET_RESET", "earliest")
    )
    
    # Multi-broker specific settings for fault tolerance
    replication_factor: int = Field(
        default_factory=lambda: yaml_config.get('kafka', {}).get('replication_factor') or 
                        int(os.getenv("KAFKA_REPLICATION_FACTOR", "3"))
    )
    
    partitions: int = Field(
        default_factory=lambda: yaml_config.get('kafka', {}).get('partitions') or 
                        int(os.getenv("KAFKA_PARTITIONS", "6"))
    )

    # Topic config
    topic_config: Dict[str, Any] = Field(
        default_factory=lambda: yaml_config.get('kafka', {}).get('topic_config') or {
            'min_insync_replicas': 2,
            'retention_ms': 604800000,  # 7 days
            'cleanup_policy': 'delete'
        }
    )
    
    # Get list of brokers for programmatic access
    @property
    def broker_list(self) -> List[str]:
        """
        Get list of broker addresses from the bootstrap_servers string.
        
        Returns:
            List of broker addresses
        """
        return self.bootstrap_servers.split(',')
    
    # Avro topic name with .value suffix for Schema Registry
    @property
    def avro_value_subject(self) -> str:
        """
        Get the Schema Registry subject name for the topic value schema.
        
        Returns:
            Subject name for the value schema
        """
        return f"{self.topic_name}-value"

class MQTTSettings(BaseSettings):
    """
    MQTT configuration settings for RuuviTag adapter

    Attributes
        broker_host: MQTT broker hostname or IP
        broker_port: MQTT broker port
        topic: MQTT topic to subscribe to
        client_id: MQTT client ID
        qos: Quality of Service level
        keep_alive: Keep alive interval in seconds
        reconnect_interval: Reconnect interval in seconds
        username: MQTT username (optional)
        password: MQTT password (optional)
    """

    broker_host: str = Field(
        default_factory=lambda: yaml_config.get('mqtt', {}).get('broker_host') or
                        os.getenv("MQTT_BROKER", "192.168.50.240")
    )

    broker_port: int = Field(
        default_factory=lambda: yaml_config.get('mqtt', {}).get('broker_port') or 
                        int(os.getenv("MQTT_PORT", "1883"))
    )
    
    topic: str = Field(
        default_factory=lambda: yaml_config.get('mqtt', {}).get('topic') or 
                        os.getenv("MQTT_TOPIC", "ruuvitag/data")
    )
    
    client_id: str = Field(
        default_factory=lambda: yaml_config.get('mqtt', {}).get('client_id') or 
                        os.getenv("MQTT_CLIENT_ID", "ruuvitag_adapter")
    )
    
    qos: int = Field(
        default_factory=lambda: yaml_config.get('mqtt', {}).get('qos') or 
                        int(os.getenv("MQTT_QOS", "1"))
    )
    
    keep_alive: int = Field(
        default_factory=lambda: yaml_config.get('mqtt', {}).get('keep_alive') or 
                        int(os.getenv("MQTT_KEEP_ALIVE", "60"))
    )
    
    reconnect_interval: int = Field(
        default_factory=lambda: yaml_config.get('mqtt', {}).get('reconnect_interval') or 
                        int(os.getenv("MQTT_RECONNECT_INTERVAL", "10"))
    )
    
    # username: Optional[str] = Field(
    #     default_factory=lambda: yaml_config.get('mqtt', {}).get('username') or 
    #                     os.getenv("MQTT_USERNAME", None)
    # )
    
    # password: Optional[str] = Field(
    #     default_factory=lambda: yaml_config.get('mqtt', {}).get('password') or 
    #                     os.getenv("MQTT_PASSWORD", None)
    # )

class SchemaRegistrySettings(BaseSettings):
    """
    Schema Registry configuration settings.
    
    Attributes:
        url: URL of the Schema Registry service
        auto_register_schemas: Whether to automatically register schemas
        compatibility_level: Schema compatibility level (e.g., BACKWARD, FORWARD, FULL)
        subject_name_strategy: Strategy for subject naming
        schema_dir: schema directory
        serialize_format: serialization format (avro, parquet, json, etc.)
        kafka_bootstrap_servers: Tells Schema Registry how to connect to Kafka
        kafkastore_topic_replication_factor: Defines the replication factor for the internal topic used by Schema Registry to store Avro/Protobuf/JSON schema definitions.
    """
    url: str = Field(
        default_factory=lambda: yaml_config.get('schema_registry', {}).get('url') or 
                        os.getenv("SCHEMA_REGISTRY_URL", "http://schema-registry:8081")
    )
    
    auto_register_schemas: bool = Field(
        default_factory=lambda: yaml_config.get('schema_registry', {}).get('auto_register_schemas') or 
                        os.getenv("SCHEMA_AUTO_REGISTER", "True").lower() in ("true", "1", "yes")
    )
    
    compatibility_level: str = Field(
        default_factory=lambda: yaml_config.get('schema_registry', {}).get('compatibility_level') or 
                        os.getenv("SCHEMA_REGISTRY_AVRO_COMPATIBILITY_LEVEL", "BACKWARD")
    )
    
    subject_name_strategy: str = Field(
        default_factory=lambda: yaml_config.get('schema_registry', {}).get('subject_name_strategy') or 
                        os.getenv("SCHEMA_SUBJECT_STRATEGY", "TopicNameStrategy")
    )
    
    # Schema paths
    schema_dir: str = Field(
        default_factory=lambda: yaml_config.get('schema_registry', {}).get('schema_dir') or 
                        os.getenv("SCHEMA_DIR", "src/schemas")
    )
    
    sensor_schema_file: str = Field(
        default_factory=lambda: yaml_config.get('schema_registry', {}).get('sensor_schema_file') or 
                        os.getenv("SENSOR_SCHEMA_FILE", "iot_sensor_reading.avsc")
    )
    
    # Serialization settings
    serialize_format: str = Field(
        default_factory=lambda: yaml_config.get('schema_registry', {}).get('serialize_format') or 
                       os.getenv("SERIALIZE_FORMAT", "avro")
    )

    # Replication factor for schemas topic
    kafka_bootstrap_servers: str = Field(
        default_factory=lambda: yaml_config.get('schema_registry', {}).get('kafka_bootstrap_servers') or 
                       os.getenv("SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS", "kafka1:9092,kafka2:9092,kafka3:9092")
    )

    kafkastore_topic_replication_factor: int = Field(
        default_factory=lambda: yaml_config.get('schema_registry', {}).get('kafkastore_topic_replication_factor') or 
                       int(os.getenv("SCHEMA_REGISTRY_KAFKASTORE_TOPIC_REPLICATION_FACTOR", "3"))
    )
    
    @property
    def sensor_schema_path(self) -> str:
        """
        Get the full path to the sensor schema file.
        
        Returns:
            Full path to the sensor schema file
        """
        return os.path.join(self.schema_dir, self.sensor_schema_file)

class RuuviTagSettings(BaseSettings):
    """
    RuuviTag configuration settings.
    
    Attributes:
        device_type: Device name
        default_location: Default location for RuuviTags
        battery: Battery parameters
        anomaly_thresholds: Thresholds for anomaly detection
        signal_strength: Signal strength
        firmware_version: Firmware's version
    """
    device_type: str = Field(
        default_factory=lambda:yaml_config.get('device_type', {}).get('device_type') or
                        os.getenv("DEVICE_TYPE", "RuuviTag")
    )

    default_location: Dict[str, Any] = Field(
        default_factory=lambda: yaml_config.get('ruuvitag', {}).get('default_location') or {
            "latitude": 60.1699,
            "longitude": 24.9384,
            "building": "building-1",
            "floor": 1,
            "zone": "main",
            "room": "room-101"
        }
    )

    battery: Dict[str, float] = Field(
        default_factory=lambda: yaml_config.get('ruuvitag', {}).get('battery') or {
            "min_voltage": 2.0,
            "max_voltage": 3.0
        }
    )

    anomaly_thresholds: Dict[str, Any] = Field(
        default_factory=lambda: yaml_config.get('ruuvitag', {}).get('anomaly_thresholds') or {
            "temperature_min": -40,
            "temperature_max": 85,
            "humidity_min": 0,
            "humidity_max": 100,
            "pressure_min": 85000,
            "pressure_max": 115000,
            "battery_low": 2.0
        }
    )

    signal_strength: Optional[int] = Field(
        default_factory=lambda: yaml_config.get('ruuvitag', {}).get('signal_strength') or
                        os.getenv("SIGNAL_STRENGTH", None)
    )

    firmware_version: Optional[int] = Field(
        default_factory=lambda: yaml_config.get('ruuvitag', {}).get('firmware_version') or
                        os.getenv("FIRMWARE_VERSION", None)
    )

class FlinkJobManagerSettings(BaseSettings):
    """Flink JobManager settings"""
    
    host: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('jobmanager', {}).get('host') or
                        os.getenv("FLINK_JOBMANAGER_HOST", "flink-jobmanager")
    )
    
    port: int = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('jobmanager', {}).get('port') or
                        int(os.getenv("FLINK_JOBMANAGER_PORT", "6123"))
    )
    
    web_port: int = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('jobmanager', {}).get('web_port') or
                        int(os.getenv("FLINK_JOBMANAGER_WEB_PORT", "8081"))
    )
    
    rpc_address: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('jobmanager', {}).get('rpc_address') or
                        os.getenv("FLINK_JOBMANAGER_RPC_ADDRESS", "flink-jobmanager")
    )
    
    memory_process_size: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('jobmanager', {}).get('memory_process_size') or
                        os.getenv("FLINK_JOBMANAGER_MEMORY", "2048m")
    )

class FlinkTaskManagerSettings(BaseSettings):
    """Flink TaskManager settings"""
    
    memory_jvm_overhead_min: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('taskmanager', {}).get('memory_jvm_overhead_min') or
                        os.getenv("MEMORY_JVM_OVERHEAD_MIN", "512m")
    )
    
    memory_jvm_overhead_max: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('taskmanager', {}).get('memory_jvm_overhead_max') or
                        os.getenv("MEMORY_JVM_OVERHEAD_MAX", "2048m")
    )

    memory_process_size: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('taskmanager', {}).get('memory_process_size') or
                        os.getenv("FLINK_TASKMANAGER_MEMORY", "4096m")
    )

class FlinkJobsSettings(BaseSettings):
    """Flink Jobs configuration"""
    
    auto_submit: bool = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('jobs', {}).get('auto_submit') or
                        os.getenv("FLINK_AUTO_SUBMIT", "True").lower() in ("true", "1", "yes")
    )
    
    retry_failed: bool = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('jobs', {}).get('retry_failed') or
                        os.getenv("FLINK_RETRY_FAILED", "True").lower() in ("true", "1", "yes")
    )
    
    health_check_interval: int = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('jobs', {}).get('health_check_interval') or
                        int(os.getenv("FLINK_HEALTH_CHECK_INTERVAL", "30"))
    )
    
    max_retry_attempts: int = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('jobs', {}).get('max_retry_attempts') or
                        int(os.getenv("FLINK_MAX_RETRY_ATTEMPTS", "3"))
    )
    
    retry_delay_seconds: int = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('jobs', {}).get('retry_delay_seconds') or
                        int(os.getenv("FLINK_RETRY_DELAY", "60"))
    )

class FlinkSettings(BaseSettings):
    """Flink configuration settings"""
    
    jobmanager: FlinkJobManagerSettings = FlinkJobManagerSettings()
    taskmanager: FlinkTaskManagerSettings = FlinkTaskManagerSettings()
    jobs: FlinkJobsSettings = FlinkJobsSettings()
    
    # Execution settings
    parallelism_default: int = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('execution', {}).get('parallelism_default') or
                        int(os.getenv("FLINK_PARALLELISM_DEFAULT", "2"))
    )
    
    runtime_mode: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('execution', {}).get('runtime_mode') or
                        os.getenv("FLINK_RUNTIME_MODE", "STREAMING")
    )
    
    # Checkpointing settings
    checkpointing_interval: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('checkpointing', {}).get('interval') or
                        os.getenv("FLINK_CHECKPOINTING_INTERVAL", "60s")
    )
    
    checkpointing_timeout: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('checkpointing', {}).get('timeout') or
                        os.getenv("FLINK_CHECKPOINTING_TIMEOUT", "300s")
    )
    
    # State backend settings
    state_backend: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('state', {}).get('backend') or
                        os.getenv("FLINK_STATE_BACKEND", "filesystem")
    )
    
    state_checkpoints_dir: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('state', {}).get('checkpoints_dir') or
                        os.getenv("FLINK_STATE_CHECKPOINTS_DIR", "s3a://iceberg-staging/checkpoints")
    )
    
    state_savepoints_dir: str = Field(
        default_factory=lambda: yaml_config.get('flink', {}).get('state', {}).get('savepoints_dir') or
                        os.getenv("FLINK_STATE_SAVEPOINTS_DIR", "s3a://iceberg-staging/savepoints")
    )

class IcebergCatalogSettings(BaseSettings):
    """Iceberg Catalog settings"""
    
    name: str = Field(
        default_factory=lambda: yaml_config.get('iceberg', {}).get('catalog', {}).get('name') or
                        os.getenv("ICEBERG_CATALOG_NAME", "iot_catalog")
    )
    
    type: str = Field(
        default_factory=lambda: yaml_config.get('iceberg', {}).get('catalog', {}).get('type') or
                        os.getenv("ICEBERG_CATALOG_TYPE", "rest")
    )
    
    uri: str = Field(
        default_factory=lambda: yaml_config.get('iceberg', {}).get('catalog', {}).get('uri') or
                        os.getenv("ICEBERG_CATALOG_URI", "http://iceberg-rest:8181")
    )
    
    warehouse: str = Field(
        default_factory=lambda: yaml_config.get('iceberg', {}).get('catalog', {}).get('warehouse') or
                        os.getenv("ICEBERG_WAREHOUSE", "s3a://iceberg-warehouse/")
    )
    
    impl: str = Field(
        default_factory=lambda: yaml_config.get('iceberg', {}).get('catalog', {}).get('impl') or
                        os.getenv("ICEBERG_CATALOG_IMPL", "org.apache.iceberg.rest.RESTCatalog")
    )

class IcebergStorageSettings(BaseSettings):
   """Iceberg Storage settings"""
   
   type: str = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('storage', {}).get('type') or
                       os.getenv("ICEBERG_STORAGE_TYPE", "s3")
   )
   
   endpoint: str = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('storage', {}).get('endpoint') or
                       os.getenv("MINIO_ENDPOINT", "http://minio:9000")
   )
   
   access_key: str = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('storage', {}).get('access_key') or
                       os.getenv("MINIO_ACCESS_KEY", "minioadmin")
   )
   
   secret_key: str = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('storage', {}).get('secret_key') or
                       os.getenv("MINIO_SECRET_KEY", "minioadmin")
   )
   
   path_style_access: bool = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('storage', {}).get('path_style_access') or
                       os.getenv("ICEBERG_PATH_STYLE_ACCESS", "True").lower() in ("true", "1", "yes")
   )
   
   region: str = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('storage', {}).get('region') or
                       os.getenv("ICEBERG_REGION", "north")
   )

class IcebergTablesSettings(BaseSettings):
   """Iceberg Tables settings"""
   
   namespace: str = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('tables', {}).get('namespace') or
                       os.getenv("ICEBERG_NAMESPACE", "iot_data")
   )
   
   raw_data_table: str = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('tables', {}).get('raw_data_table') or
                       os.getenv("ICEBERG_RAW_DATA_TABLE", "sensor_readings")
   )
   
   aggregated_table: str = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('tables', {}).get('aggregated_table') or
                       os.getenv("ICEBERG_AGGREGATED_TABLE", "sensor_readings_hourly")
   )
   
   partitioning: Dict[str, Any] = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('tables', {}).get('partitioning') or {
           'device_buckets': 16,
           'time_granularity': 'day'
       }
   )
   
   properties: Dict[str, Any] = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('tables', {}).get('properties') or {
           'format_version': 2,
           'compression': 'snappy',
           'delete_after_commit': True,
           'previous_versions_max': 10,
           'target_file_size_mb': 128
       }
   )

class IcebergSettings(BaseSettings):
   """Iceberg configuration settings"""
   
   catalog: IcebergCatalogSettings = IcebergCatalogSettings()
   storage: IcebergStorageSettings = IcebergStorageSettings()
   tables: IcebergTablesSettings = IcebergTablesSettings()
   
   # Write optimization
   write_distribution_mode: str = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('write', {}).get('distribution_mode') or
                       os.getenv("ICEBERG_WRITE_DISTRIBUTION_MODE", "hash")
   )
   
   write_target_file_size_mb: int = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('write', {}).get('target_file_size_mb') or
                       int(os.getenv("ICEBERG_WRITE_TARGET_FILE_SIZE_MB", "128"))
   )
   
   auto_compaction: bool = Field(
       default_factory=lambda: yaml_config.get('iceberg', {}).get('write', {}).get('auto_compaction') or
                       os.getenv("ICEBERG_AUTO_COMPACTION", "True").lower() in ("true", "1", "yes")
   )

class PostgreSQLSettings(BaseSettings):
   """PostgreSQL configuration settings"""
   
   host: str = Field(
       default_factory=lambda: yaml_config.get('postgres', {}).get('host') or
                       os.getenv("POSTGRES_HOST", "postgres")
   )
   
   port: int = Field(
       default_factory=lambda: yaml_config.get('postgres', {}).get('port') or
                       int(os.getenv("POSTGRES_PORT", "5432"))
   )
   
   database: str = Field(
       default_factory=lambda: yaml_config.get('postgres', {}).get('database') or
                       os.getenv("POSTGRES_DB", "iceberg_catalog")
   )
   
   username: str = Field(
       default_factory=lambda: yaml_config.get('postgres', {}).get('username') or
                       os.getenv("POSTGRES_USER", "iceberg")
   )
   
   password: str = Field(
       default_factory=lambda: yaml_config.get('postgres', {}).get('password') or
                       os.getenv("POSTGRES_PASSWORD", "iceberg")
   )
   
   schema: str = Field(
       default_factory=lambda: yaml_config.get('postgres', {}).get('schema') or
                       os.getenv("POSTGRES_SCHEMA", "iceberg")
   )
   
   auto_create_schema: bool = Field(
       default_factory=lambda: yaml_config.get('postgres', {}).get('auto_create_schema') or
                       os.getenv("POSTGRES_AUTO_CREATE_SCHEMA", "True").lower() in ("true", "1", "yes")
   )
   
   pool: Dict[str, int] = Field(
       default_factory=lambda: yaml_config.get('postgres', {}).get('pool') or {
           'min_connections': 5,
           'max_connections': 20,
           'connection_timeout': 30
       }
   )
   
   @property
   def connection_url(self) -> str:
       """Get PostgreSQL connection URL"""
       return f"postgresql://{self.username}:{self.password}@{self.host}:{self.port}/{self.database}"

class MinIOSettings(BaseSettings):
   """MinIO configuration settings"""
   
   endpoint: str = Field(
       default_factory=lambda: yaml_config.get('minio', {}).get('endpoint') or
                       os.getenv("MINIO_ENDPOINT", "http://minio:9000")
   )
   
   access_key: str = Field(
       default_factory=lambda: yaml_config.get('minio', {}).get('access_key') or
                       os.getenv("MINIO_ACCESS_KEY", "minioadmin")
   )
   
   secret_key: str = Field(
       default_factory=lambda: yaml_config.get('minio', {}).get('secret_key') or
                       os.getenv("MINIO_SECRET_KEY", "minioadmin")
   )
   
   region: str = Field(
       default_factory=lambda: yaml_config.get('minio', {}).get('region') or
                       os.getenv("MINIO_REGION", "north")
   )
   
   console_port: int = Field(
       default_factory=lambda: yaml_config.get('minio', {}).get('console_port') or
                       int(os.getenv("MINIO_CONSOLE_PORT", "9002"))
   )
   
   buckets: Dict[str, str] = Field(
       default_factory=lambda: yaml_config.get('minio', {}).get('buckets') or {
           'warehouse': 'iceberg-warehouse',
           'staging': 'iceberg-staging'
       }
   )

class MonitoringMetricsSettings(BaseSettings):
   """Monitoring Metrics settings"""
   
   enabled: bool = Field(
       default_factory=lambda: yaml_config.get('monitoring', {}).get('metrics', {}).get('enabled') or
                       os.getenv("MONITORING_METRICS_ENABLED", "True").lower() in ("true", "1", "yes")
   )
   
   interval_ms: int = Field(
       default_factory=lambda: yaml_config.get('monitoring', {}).get('metrics', {}).get('interval_ms') or
                       int(os.getenv("MONITORING_METRICS_INTERVAL_MS", "60000"))
   )
   
   flink: Dict[str, bool] = Field(
       default_factory=lambda: yaml_config.get('monitoring', {}).get('metrics', {}).get('flink') or {
           'job_metrics': True,
           'task_metrics': True,
           'checkpoint_metrics': True
       }
   )
   
   kafka: Dict[str, bool] = Field(
       default_factory=lambda: yaml_config.get('monitoring', {}).get('metrics', {}).get('kafka') or {
           'consumer_lag_metrics': True,
           'producer_metrics': True
       }
   )

class MonitoringAlertsSettings(BaseSettings):
   """Monitoring Alerts settings"""
   
   kafka_lag_threshold: int = Field(
       default_factory=lambda: yaml_config.get('monitoring', {}).get('alerts', {}).get('kafka_lag_threshold') or
                       int(os.getenv("MONITORING_KAFKA_LAG_THRESHOLD", "10000"))
   )
   
   flink_restart_threshold: int = Field(
       default_factory=lambda: yaml_config.get('monitoring', {}).get('alerts', {}).get('flink_restart_threshold') or
                       int(os.getenv("MONITORING_FLINK_RESTART_THRESHOLD", "3"))
   )
   
   flink_checkpoint_failure_threshold: int = Field(
       default_factory=lambda: yaml_config.get('monitoring', {}).get('alerts', {}).get('flink_checkpoint_failure_threshold') or
                       int(os.getenv("MONITORING_FLINK_CHECKPOINT_FAILURE_THRESHOLD", "5"))
   )
   
   cpu_threshold: int = Field(
       default_factory=lambda: yaml_config.get('monitoring', {}).get('alerts', {}).get('cpu_threshold') or
                       int(os.getenv("MONITORING_CPU_THRESHOLD", "80"))
   )
   
   memory_threshold: int = Field(
       default_factory=lambda: yaml_config.get('monitoring', {}).get('alerts', {}).get('memory_threshold') or
                       int(os.getenv("MONITORING_MEMORY_THRESHOLD", "85"))
   )
   
   disk_threshold: int = Field(
       default_factory=lambda: yaml_config.get('monitoring', {}).get('alerts', {}).get('disk_threshold') or
                       int(os.getenv("MONITORING_DISK_THRESHOLD", "90"))
   )

class MonitoringSettings(BaseSettings):
   """Monitoring configuration settings"""
   
   health_check_interval_ms: int = Field(
       default_factory=lambda: yaml_config.get('monitoring', {}).get('health_check_interval_ms') or
                       int(os.getenv("MONITORING_HEALTH_CHECK_INTERVAL_MS", "30000"))
   )
   
   metrics: MonitoringMetricsSettings = MonitoringMetricsSettings()
   alerts: MonitoringAlertsSettings = MonitoringAlertsSettings()

class JobSubmissionSettings(BaseSettings):
   """Job Submission configuration settings"""
   
   max_retries: int = Field(
       default_factory=lambda: yaml_config.get('job_submission', {}).get('max_retries') or
                       int(os.getenv("JOB_SUBMISSION_MAX_RETRIES", "5"))
   )
   
   retry_delay_seconds: int = Field(
       default_factory=lambda: yaml_config.get('job_submission', {}).get('retry_delay_seconds') or
                       int(os.getenv("JOB_SUBMISSION_RETRY_DELAY_SECONDS", "30"))
   )
   
   exponential_backoff: bool = Field(
       default_factory=lambda: yaml_config.get('job_submission', {}).get('exponential_backoff') or
                       os.getenv("JOB_SUBMISSION_EXPONENTIAL_BACKOFF", "True").lower() in ("true", "1", "yes")
   )
   
   wait_for_cluster_timeout: int = Field(
       default_factory=lambda: yaml_config.get('job_submission', {}).get('wait_for_cluster_timeout') or
                       int(os.getenv("JOB_SUBMISSION_WAIT_FOR_CLUSTER_TIMEOUT", "300"))
   )
   
   cluster_health_check_interval: int = Field(
       default_factory=lambda: yaml_config.get('job_submission', {}).get('cluster_health_check_interval') or
                       int(os.getenv("JOB_SUBMISSION_CLUSTER_HEALTH_CHECK_INTERVAL", "10"))
   )
   
   monitor_jobs: bool = Field(
       default_factory=lambda: yaml_config.get('job_submission', {}).get('monitor_jobs') or
                       os.getenv("JOB_SUBMISSION_MONITOR_JOBS", "True").lower() in ("true", "1", "yes")
   )
   
   monitoring_interval: int = Field(
       default_factory=lambda: yaml_config.get('job_submission', {}).get('monitoring_interval') or
                       int(os.getenv("JOB_SUBMISSION_MONITORING_INTERVAL", "30"))
   )
   
   sql_execution_timeout: int = Field(
       default_factory=lambda: yaml_config.get('job_submission', {}).get('sql_execution_timeout') or
                       int(os.getenv("JOB_SUBMISSION_SQL_EXECUTION_TIMEOUT", "60"))
   )
   
   statement_execution_delay: int = Field(
       default_factory=lambda: yaml_config.get('job_submission', {}).get('statement_execution_delay') or
                       int(os.getenv("JOB_SUBMISSION_STATEMENT_EXECUTION_DELAY", "2"))
   )

class ProducerSettings(BaseSettings):
    """
    Kafka Producer specific settings.
    
    Attributes:
        client_id: Client ID for the producer
        acks: Acknowledgement level
        retries: Number of retries
        retry_backoff_ms: Backoff time between retries
    """
    client_id: str = Field(
        default_factory=lambda: yaml_config.get('producer', {}).get('client_id') or 
                        os.getenv("PRODUCER_CLIENT_ID", "iot-data-producer")
    )
    
    acks: str = Field(
        default_factory=lambda: yaml_config.get('producer', {}).get('acks') or 
                        os.getenv("PRODUCER_ACKS", "all")
    )
    
    retries: int = Field(
        default_factory=lambda: yaml_config.get('producer', {}).get('retries') or 
                        int(os.getenv("PRODUCER_RETRIES", "5"))
    )
    
    retry_backoff_ms: int = Field(
        default_factory=lambda: yaml_config.get('producer', {}).get('retry_backoff_ms') or 
                        int(os.getenv("PRODUCER_RETRY_BACKOFF_MS", "500"))
    )
    
    max_in_flight_requests_per_connection: int = Field(
        default_factory=lambda: yaml_config.get('producer', {}).get('max_in_flight_requests_per_connection') or 
                        int(os.getenv("PRODUCER_MAX_IN_FLIGHT", "1"))
    )
    
    # Performance tuning
    queue_buffering_max_ms: int = Field(
        default_factory=lambda: yaml_config.get('producer', {}).get('queue_buffering_max_ms') or 
                        int(os.getenv("PRODUCER_QUEUE_BUFFERING_MAX_MS", "5"))
    )
    
    queue_buffering_max_kbytes: int = Field(
        default_factory=lambda: yaml_config.get('producer', {}).get('queue_buffering_max_kbytes') or 
                        int(os.getenv("PRODUCER_QUEUE_BUFFERING_MAX_KBYTES", "32768"))
    )
    
    batch_num_messages: int = Field(
        default_factory=lambda: yaml_config.get('producer', {}).get('batch_num_messages') or 
                        int(os.getenv("PRODUCER_BATCH_NUM_MESSAGES", "1000"))
    )
    
    socket_timeout_ms: int = Field(
        default_factory=lambda: yaml_config.get('producer', {}).get('socket_timeout_ms') or 
                        int(os.getenv("PRODUCER_SOCKET_TIMEOUT_MS", "30000"))
    )
    
    message_timeout_ms: int = Field(
        default_factory=lambda: yaml_config.get('producer', {}).get('message_timeout_ms') or 
                        int(os.getenv("PRODUCER_MESSAGE_TIMEOUT_MS", "10000"))
    )
    
    # Compression
    compression_type: str = Field(
        default_factory=lambda: yaml_config.get('producer', {}).get('compression_type') or 
                        os.getenv("PRODUCER_COMPRESSION_TYPE", "snappy")
    )
    
    def get_config(self) -> Dict[str, Any]:
        """
        Get producer configuration as a dictionary for Confluent Kafka.
        
        Returns:
            Dictionary with producer configuration
        """
        return {
            'bootstrap.servers': settings.kafka.bootstrap_servers,
            'client.id': self.client_id,
            'acks': self.acks,
            'retries': self.retries,
            'retry.backoff.ms': self.retry_backoff_ms,
            'max.in.flight.requests.per.connection': self.max_in_flight_requests_per_connection,
            'queue.buffering.max.ms': self.queue_buffering_max_ms,
            'queue.buffering.max.kbytes': self.queue_buffering_max_kbytes,
            'batch.num.messages': self.batch_num_messages,
            'socket.timeout.ms': self.socket_timeout_ms,
            'message.timeout.ms': self.message_timeout_ms,
            'compression.type': self.compression_type
        }

class ConsumerSettings(BaseSettings):
    """
    Kafka Consumer specific settings.
    
    Attributes:
        enable_auto_commit: Whether to automatically commit offsets
        auto_commit_interval_ms: Interval between auto commits
        fetch_min_bytes: Minimum bytes to fetch
    """
    enable_auto_commit: bool = Field(
        default_factory=lambda: yaml_config.get('consumer', {}).get('enable_auto_commit') or 
                        os.getenv("CONSUMER_ENABLE_AUTO_COMMIT", "True").lower() in ("true", "1", "yes")
    )
    
    auto_commit_interval_ms: int = Field(
        default_factory=lambda: yaml_config.get('consumer', {}).get('auto_commit_interval_ms') or 
                        int(os.getenv("CONSUMER_AUTO_COMMIT_INTERVAL_MS", "5000"))
    )
    
    fetch_min_bytes: int = Field(
        default_factory=lambda: yaml_config.get('consumer', {}).get('fetch_min_bytes') or 
                        int(os.getenv("CONSUMER_FETCH_MIN_BYTES", "1"))
    )
    
    # Fault tolerance settings
    session_timeout_ms: int = Field(
        default_factory=lambda: yaml_config.get('consumer', {}).get('session_timeout_ms') or 
                        int(os.getenv("CONSUMER_SESSION_TIMEOUT_MS", "30000"))
    )
    
    heartbeat_interval_ms: int = Field(
        default_factory=lambda: yaml_config.get('consumer', {}).get('heartbeat_interval_ms') or 
                        int(os.getenv("CONSUMER_HEARTBEAT_INTERVAL_MS", "10000"))
    )
    
    max_poll_interval_ms: int = Field(
        default_factory=lambda: yaml_config.get('consumer', {}).get('max_poll_interval_ms') or 
                        int(os.getenv("CONSUMER_MAX_POLL_INTERVAL_MS", "300000"))
    )
    
    # Load balancing
    partition_assignment_strategy: str = Field(
        default_factory=lambda: yaml_config.get('consumer', {}).get('partition_assignment_strategy') or 
                        os.getenv("CONSUMER_PARTITION_ASSIGNMENT_STRATEGY", "cooperative-sticky")
    )
    
    def get_config(self, group_id: str = None, auto_offset_reset: str = None) -> Dict[str, Any]:
        """
        Get consumer configuration as a dictionary for Confluent Kafka.
        
        Args:
            group_id: Optional consumer group ID (overrides default)
            auto_offset_reset: Optional auto offset reset strategy (overrides default)
            
        Returns:
            Dictionary with consumer configuration
        """
        return {
            'bootstrap.servers': settings.kafka.bootstrap_servers,
            'group.id': group_id or settings.kafka.consumer_group_id,
            'auto.offset.reset': auto_offset_reset or settings.kafka.auto_offset_reset,
            'enable.auto.commit': self.enable_auto_commit,
            'auto.commit.interval.ms': self.auto_commit_interval_ms,
            'fetch.min.bytes': self.fetch_min_bytes,
            'session.timeout.ms': self.session_timeout_ms,
            'heartbeat.interval.ms': self.heartbeat_interval_ms,
            'max.poll.interval.ms': self.max_poll_interval_ms,
            'partition.assignment.strategy': self.partition_assignment_strategy
        }

class IoTSimulatorSettings(BaseSettings):
    """
    IoT simulator configuration settings.
    
    Attributes:
        num_devices: Number of simulated IoT devices
        data_generation_interval_sec: Interval between data generation in seconds
        device_types: List of device types to simulate
        anomaly_probability: Probability of generating an anomalous reading
    """
    num_devices: int = Field(
        default_factory=lambda: yaml_config.get('iot_simulator', {}).get('num_devices') or 
                        int(os.getenv("IOT_NUM_DEVICES", "8"))
    )
    
    data_generation_interval_sec: float = Field(
        default_factory=lambda: yaml_config.get('iot_simulator', {}).get('data_generation_interval_sec') or 
                        float(os.getenv("IOT_DATA_INTERVAL_SEC", "1.0"))
    )
    
    # Additional simulation parameters
    device_types: List[str] = Field(
        default_factory=lambda: yaml_config.get('iot_simulator', {}).get('device_types') or 
                        os.getenv("IOT_DEVICE_TYPES", "temperature,humidity,pressure,motion,light").split(',')
    )
    
    anomaly_probability: float = Field(
        default_factory=lambda: yaml_config.get('iot_simulator', {}).get('anomaly_probability') or 
                        float(os.getenv("IOT_ANOMALY_PROBABILITY", "0.05"))
    )

    @field_validator('device_types')
    def validate_device_types(cls, v):
        """Validate device types and convert to list if it's a string"""
        if isinstance(v, str):
            return v.split(',')
        return v

class LoggingSettings(BaseSettings):
    """
    Logging configuration settings.
    
    Attributes:
        level: Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        format: Log format string
    """
    level: str = Field(
        default_factory=lambda: yaml_config.get('logging', {}).get('level') or 
                        os.getenv("LOG_LEVEL", "INFO")
    )
    
    format: str = Field(
        default_factory=lambda: yaml_config.get('logging', {}).get('format') or 
                        os.getenv("LOG_FORMAT", "<green>{time:YYYY-MM-DD HH:mm:ss.SSS}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>")
    )

    # File logging settings
    file_logging_enabled: bool = Field(
        default_factory=lambda: yaml_config.get('logging', {}).get('file_logging', {}).get('enabled') or 
                        os.getenv("LOG_FILE_ENABLED", "False").lower() in ("true", "1", "yes")
    )
    
    log_dir: str = Field(
        default_factory=lambda: yaml_config.get('logging', {}).get('file_logging', {}).get('log_dir') or 
                        os.getenv("LOG_DIR", "logs")
    )
    
    max_size: str = Field(
        default_factory=lambda: yaml_config.get('logging', {}).get('file_logging', {}).get('max_size') or 
                        os.getenv("LOG_MAX_SIZE", "10MB")
    )
    
    retention: str = Field(
        default_factory=lambda: yaml_config.get('logging', {}).get('file_logging', {}).get('retention') or 
                        os.getenv("LOG_RETENTION", "1 week")
    )
    
    compression: str = Field(
        default_factory=lambda: yaml_config.get('logging', {}).get('file_logging', {}).get('compression') or 
                        os.getenv("LOG_COMPRESSION", "zip")
    )
    
    # Error log specific settings
    error_log_enabled: bool = Field(
        default_factory=lambda: yaml_config.get('logging', {}).get('file_logging', {}).get('error_log', {}).get('enabled') or 
                        os.getenv("ERROR_LOG_ENABLED", "False").lower() in ("true", "1", "yes")
    )
    
    error_log_retention: str = Field(
        default_factory=lambda: yaml_config.get('logging', {}).get('file_logging', {}).get('error_log', {}).get('retention') or 
                        os.getenv("ERROR_LOG_RETENTION", "1 month")
    )
 
class Settings(BaseSettings):
    """Global application settings."""
    app_name: str = Field(
        default_factory=lambda: yaml_config.get('app', {}).get('name') or 
                        os.getenv("APP_NAME", "IoT Data Pipeline (Multi-Broker with Schema Registry)")
    )
    
    environment: str = Field(
        default_factory=lambda: yaml_config.get('app', {}).get('environment') or 
                        os.getenv("ENVIRONMENT", "development")
    )

    kafka: KafkaSettings = KafkaSettings()
    mqtt: MQTTSettings = MQTTSettings()
    schema_registry: SchemaRegistrySettings = SchemaRegistrySettings()
    ruuvitag: RuuviTagSettings = RuuviTagSettings()
    flink: FlinkSettings = FlinkSettings()
    iceberg: IcebergSettings = IcebergSettings()
    postgres: PostgreSQLSettings = PostgreSQLSettings()
    minio: MinIOSettings = MinIOSettings()
    monitoring: MonitoringSettings = MonitoringSettings()
    job_submission: JobSubmissionSettings = JobSubmissionSettings()
    producer: ProducerSettings = ProducerSettings()
    consumer: ConsumerSettings = ConsumerSettings()
    iot_simulator: IoTSimulatorSettings = IoTSimulatorSettings()
    logging: LoggingSettings = LoggingSettings()

    class Config:
        """Configuration for the Settings class."""
        env_file = ".env"
        case_sensitive = False

# Create a singleton instance of the Settings class
settings = Settings()