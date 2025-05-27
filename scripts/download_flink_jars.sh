#!/bin/bash
# Download Required Flink JARs for Kafka, Avro, and Iceberg Integration

set -e

# Create jars directory if it doesn't exist
mkdir -p jars

echo "Downloading Flink connector JARs for ARM64 compatibility..."

# Base URLs for downloading JARs
MAVEN_CENTRAL="https://repo1.maven.org/maven2"
CONFLUENT_REPO="https://packages.confluent.io/maven"

# JAR versions - using versions compatible with Flink 1.19 and ARM64
FLINK_VERSION="1.19.1"
KAFKA_CONNECTOR_VERSION="3.2.0-1.19"
HADOOP_VERSION="3.3.6"
AWS_SDK_VERSION="1.12.728"
ICEBERG_VERSION="1.4.3"

# Function to download JAR if it doesn't exist
download_jar() {
    local url="$1"
    local filename="$2"
    local filepath="jars/$filename"
    
    if [ -f "$filepath" ]; then
        echo "✓ $filename already exists"
        return 0
    fi
    
    echo "Downloading $filename..."
    if curl -L -o "$filepath" "$url"; then
        echo "✓ Downloaded $filename"
    else
        echo "✗ Failed to download $filename"
        return 1
    fi
}

echo "Starting JAR downloads..."

# Flink Kafka Connector
download_jar \
    "$MAVEN_CENTRAL/org/apache/flink/flink-connector-kafka/$KAFKA_CONNECTOR_VERSION/flink-connector-kafka-$KAFKA_CONNECTOR_VERSION.jar" \
    "flink-connector-kafka-$KAFKA_CONNECTOR_VERSION.jar"

# Flink SQL Kafka Connector
download_jar \
    "$MAVEN_CENTRAL/org/apache/flink/flink-sql-connector-kafka/$KAFKA_CONNECTOR_VERSION/flink-sql-connector-kafka-$KAFKA_CONNECTOR_VERSION.jar" \
    "flink-sql-connector-kafka-$KAFKA_CONNECTOR_VERSION.jar"

# Flink Avro Support
download_jar \
    "$MAVEN_CENTRAL/org/apache/flink/flink-avro/$FLINK_VERSION/flink-avro-$FLINK_VERSION.jar" \
    "flink-avro-$FLINK_VERSION.jar"

# Flink Parquet Support
download_jar \
    "$MAVEN_CENTRAL/org/apache/flink/flink-parquet/$FLINK_VERSION/flink-parquet-$FLINK_VERSION.jar" \
    "flink-parquet-$FLINK_VERSION.jar"

# Flink File Connector
download_jar \
    "$MAVEN_CENTRAL/org/apache/flink/flink-connector-files/$FLINK_VERSION/flink-connector-files-$FLINK_VERSION.jar" \
    "flink-connector-files-$FLINK_VERSION.jar"

# Hadoop AWS for S3/MinIO support
download_jar \
    "$MAVEN_CENTRAL/org/apache/hadoop/hadoop-aws/$HADOOP_VERSION/hadoop-aws-$HADOOP_VERSION.jar" \
    "hadoop-aws-$HADOOP_VERSION.jar"

# AWS Java SDK Bundle
download_jar \
    "$MAVEN_CENTRAL/com/amazonaws/aws-java-sdk-bundle/$AWS_SDK_VERSION/aws-java-sdk-bundle-$AWS_SDK_VERSION.jar" \
    "aws-java-sdk-bundle-$AWS_SDK_VERSION.jar"

# Iceberg Flink Runtime
download_jar \
    "$MAVEN_CENTRAL/org/apache/iceberg/iceberg-flink-runtime-1.19/$ICEBERG_VERSION/iceberg-flink-runtime-1.19-$ICEBERG_VERSION.jar" \
    "iceberg-flink-runtime-1.19-$ICEBERG_VERSION.jar"

# Additional dependencies for Avro Schema Registry integration
download_jar \
    "$MAVEN_CENTRAL/io/confluent/kafka-avro-serializer/7.9.0/kafka-avro-serializer-7.9.0.jar" \
    "kafka-avro-serializer-7.9.0.jar"

download_jar \
    "$MAVEN_CENTRAL/io/confluent/kafka-schema-registry-client/7.9.0/kafka-schema-registry-client-7.9.0.jar" \
    "kafka-schema-registry-client-7.9.0.jar"

download_jar \
    "$MAVEN_CENTRAL/io/confluent/common-config/7.9.0/common-config-7.9.0.jar" \
    "common-config-7.9.0.jar"

download_jar \
    "$MAVEN_CENTRAL/io/confluent/common-utils/7.9.0/common-utils-7.9.0.jar" \
    "common-utils-7.9.0.jar"

# PostgreSQL JDBC Driver for Iceberg catalog
download_jar \
    "$MAVEN_CENTRAL/org/postgresql/postgresql/42.7.1/postgresql-42.7.1.jar" \
    "postgresql-42.7.1.jar"

# JSON processing
download_jar \
    "$MAVEN_CENTRAL/com/fasterxml/jackson/core/jackson-core/2.15.2/jackson-core-2.15.2.jar" \
    "jackson-core-2.15.2.jar"

download_jar \
    "$MAVEN_CENTRAL/com/fasterxml/jackson/core/jackson-databind/2.15.2/jackson-databind-2.15.2.jar" \
    "jackson-databind-2.15.2.jar"

download_jar \
    "$MAVEN_CENTRAL/com/fasterxml/jackson/core/jackson-annotations/2.15.2/jackson-annotations-2.15.2.jar" \
    "jackson-annotations-2.15.2.jar"

echo ""
echo "✓ All JARs downloaded successfully!"
echo ""
echo "Downloaded JARs:"
ls -la jars/

echo ""
echo "Total JAR files: $(ls jars/*.jar | wc -l)"
echo "Total size: $(du -sh jars/)"

echo ""
echo "Note: These JARs are compatible with ARM64 (Apple Silicon) architecture"
echo "and will be automatically mounted into the Flink containers."