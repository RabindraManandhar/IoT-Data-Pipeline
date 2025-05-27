
#!/bin/sh
# MinIO Setup Script - Create buckets and configure for Iceberg

set -e

echo "Setting up MinIO for PyIceberg..."

# Wait for MinIO to be ready
echo "Waiting for MinIO to be ready..."
until mc alias set myminio http://minio:9000 minioadmin minioadmin; do
  echo "MinIO not ready yet, waiting..."
  sleep 5
done

echo "MinIO is ready!"

# Create buckets for Iceberg
echo "Creating Iceberg warehouse bucket..."
mc mb myminio/iceberg-warehouse --ignore-existing

# Create bucket for staging/temp data
echo "Creating staging bucket..."
mc mb myminio/iceberg-staging --ignore-existing

# Set bucket policies for public read access if needed
echo "Setting bucket policies..."
mc anonymous set public myminio/iceberg-warehouse
mc anonymous set public myminio/iceberg-staging

# Directory structure will be created automatically when Iceberg writes files
echo "Bucket structure ready for Iceberg tables..."

# List created buckets
echo "Listing created buckets:"
mc ls myminio/

echo "MinIO setup completed successfully!"
