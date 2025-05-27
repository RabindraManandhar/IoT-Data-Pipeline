-- PostgreSQL initialization script for PyIceberg catalog
-- This script sets up the necessary tables and schemas for Iceberg catalog management

-- Create schemas
CREATE SCHEMA IF NOT EXISTS iceberg;

-- Create extension for UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Grant privileges to iceberg user
GRANT ALL PRIVILEGES ON SCHEMA iceberg TO iceberg;
GRANT ALL PRIVILEGES ON SCHEMA public TO iceberg;

-- Create catalog configuration table
CREATE TABLE IF NOT EXISTS iceberg.catalog_config (
    id SERIAL PRIMARY KEY,
    catalog_name VARCHAR(255) NOT NULL UNIQUE,
    warehouse_location VARCHAR(500) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default catalog configuration
INSERT INTO iceberg.catalog_config (catalog_name, warehouse_location) 
VALUES ('iot_catalog', 's3a://iceberg-warehouse/') 
ON CONFLICT (catalog_name) DO NOTHING;

-- Create namespace (database) registry
CREATE TABLE IF NOT EXISTS iceberg.namespaces (
    id SERIAL PRIMARY KEY,
    catalog_name VARCHAR(255) NOT NULL,
    namespace_name VARCHAR(255) NOT NULL,
    properties JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(catalog_name, namespace_name)
);

-- Insert default namespace for IoT data
INSERT INTO iceberg.namespaces (catalog_name, namespace_name, properties) 
VALUES ('iot_catalog', 'iot_data', '{"description": "IoT sensor data namespace"}')
ON CONFLICT (catalog_name, namespace_name) DO NOTHING;

-- Create table metadata registry
CREATE TABLE IF NOT EXISTS iceberg.table_metadata (
    id SERIAL PRIMARY KEY,
    catalog_name VARCHAR(255) NOT NULL,
    namespace_name VARCHAR(255) NOT NULL,
    table_name VARCHAR(255) NOT NULL,
    metadata_location VARCHAR(500) NOT NULL,
    previous_metadata_location VARCHAR(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(catalog_name, namespace_name, table_name)
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_catalog_namespace ON iceberg.namespaces(catalog_name, namespace_name);
CREATE INDEX IF NOT EXISTS idx_table_lookup ON iceberg.table_metadata(catalog_name, namespace_name, table_name);
CREATE INDEX IF NOT EXISTS idx_metadata_location ON iceberg.table_metadata(metadata_location);

-- Create function to update updated_at timestamp
CREATE OR REPLACE FUNCTION iceberg.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for automatic timestamp updates
CREATE TRIGGER update_catalog_config_updated_at BEFORE UPDATE ON iceberg.catalog_config
    FOR EACH ROW EXECUTE FUNCTION iceberg.update_updated_at_column();

CREATE TRIGGER update_table_metadata_updated_at BEFORE UPDATE ON iceberg.table_metadata
    FOR EACH ROW EXECUTE FUNCTION iceberg.update_updated_at_column();

-- Grant all privileges on tables to iceberg user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA iceberg TO iceberg;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA iceberg TO iceberg;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA iceberg TO iceberg;

-- Create view for easy table lookup
CREATE OR REPLACE VIEW iceberg.tables_view AS
SELECT 
    tm.catalog_name,
    tm.namespace_name,
    tm.table_name,
    tm.metadata_location,
    tm.created_at,
    tm.updated_at,
    n.properties as namespace_properties
FROM iceberg.table_metadata tm
JOIN iceberg.namespaces n ON tm.catalog_name = n.catalog_name AND tm.namespace_name = n.namespace_name;

GRANT SELECT ON iceberg.tables_view TO iceberg;

-- Log successful initialization
INSERT INTO iceberg.catalog_config (catalog_name, warehouse_location) 
VALUES ('_system', 'System initialized at ' || CURRENT_TIMESTAMP) 
ON CONFLICT (catalog_name) DO UPDATE SET warehouse_location = EXCLUDED.warehouse_location;