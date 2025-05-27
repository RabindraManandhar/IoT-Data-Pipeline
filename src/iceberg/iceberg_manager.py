"""
PyIceberg Manager - Handles all Iceberg operations including table management,
schema evolution, and data writing with MinIO storage and PostgreSQL catalog
"""

import os
import json
import pandas as pd
import pyarrow as pa
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional, Union
from pathlib import Path

from pyiceberg.catalog.sql import SqlCatalog
from pyiceberg.schema import Schema as IcebergSchema
from pyiceberg.types import (
    NestedField, StringType, DoubleType, BooleanType, IntegerType,
    LongType, TimestampType, StructType, ListType, MapType
)
from pyiceberg.partitioning import PartitionSpec, PartitionField
from pyiceberg.transforms import IdentityTransform, BucketTransform, HourTransform
from pyiceberg.table.sorting import SortOrder, SortField
from pyiceberg.expressions import AlwaysTrue

from src.utils.logger import log
from src.config.config import settings

class IcebergManager:
    """
    Manager class for PyIceberg operations with automatic schema evolution
    """
    
    def __init__(self):
        """Initialize the Iceberg manager"""
        self.catalog = None
        self.namespace = "iot_data"
        self.tables_cache = {}
        
        # Initialize catalog
        self._initialize_catalog()
        
        # Create namespace if it doesn't exist
        self._ensure_namespace()
        
    def _initialize_catalog(self):
        """Initialize the Iceberg catalog with PostgreSQL backend"""
        try:
            # Get configuration from environment
            catalog_uri = os.getenv('ICEBERG_CATALOG_URI', 
                                  'postgresql://iceberg:iceberg@postgres:5432/iceberg_catalog')
            warehouse_path = os.getenv('ICEBERG_WAREHOUSE_PATH', 's3a://iceberg-warehouse/')
            
            # S3/MinIO configuration
            s3_config = {
                's3.endpoint': os.getenv('MINIO_ENDPOINT', 'http://minio:9000'),
                's3.access-key-id': os.getenv('MINIO_ACCESS_KEY', 'minioadmin'),
                's3.secret-access-key': os.getenv('MINIO_SECRET_KEY', 'minioadmin'),
                's3.path-style-access': 'true',
                's3.region': 'us-east-1',  # MinIO default region
            }
            
            # Create catalog
            self.catalog = SqlCatalog(
                name="iot_catalog",
                **{
                    "uri": catalog_uri,
                    "warehouse": warehouse_path,
                    **s3_config
                }
            )
            
            log.info(f"Iceberg catalog initialized successfully")
            log.info(f"Catalog URI: {catalog_uri}")
            log.info(f"Warehouse path: {warehouse_path}")
            
        except Exception as e:
            log.error(f"Error initializing Iceberg catalog: {str(e)}")
            raise
    
    def _ensure_namespace(self):
        """Ensure the namespace (database) exists"""
        try:
            # Create namespace if it doesn't exist
            if not self.catalog.namespace_exists(self.namespace):
                self.catalog.create_namespace(
                    namespace=self.namespace,
                    properties={"description": "IoT sensor data namespace"}
                )
                log.info(f"Created namespace: {self.namespace}")
            else:
                log.info(f"Namespace already exists: {self.namespace}")
                
        except Exception as e:
            log.error(f"Error ensuring namespace: {str(e)}")
            raise
    
    def _create_iot_schema(self, sample_data: Dict[str, Any] = None) -> IcebergSchema:
        """
        Create Iceberg schema for IoT sensor data with automatic field detection
        
        Args:
            sample_data: Sample data record to infer additional fields
            
        Returns:
            Iceberg schema
        """
        try:
            # Base schema fields (always present)
            base_fields = [
                NestedField(1, "device_id", StringType(), required=True),
                NestedField(2, "device_type", StringType(), required=True),
                NestedField(3, "timestamp", TimestampType(), required=True),
                NestedField(4, "event_time", TimestampType(), required=True),
                NestedField(5, "processing_time", TimestampType(), required=True),
                NestedField(6, "value", DoubleType(), required=False),
                NestedField(7, "unit", StringType(), required=True),
                NestedField(8, "is_anomaly", BooleanType(), required=False),
                
                # Location information
                NestedField(10, "location", StructType([
                    NestedField(101, "latitude", DoubleType(), required=True),
                    NestedField(102, "longitude", DoubleType(), required=True),
                    NestedField(103, "building", StringType(), required=False),
                    NestedField(104, "floor", IntegerType(), required=False),
                    NestedField(105, "zone", StringType(), required=False),
                    NestedField(106, "room", StringType(), required=False),
                ]), required=True),
                
                # Device information
                NestedField(20, "battery_level", DoubleType(), required=False),
                NestedField(21, "signal_strength", DoubleType(), required=False),
                NestedField(22, "firmware_version", StringType(), required=False),
                NestedField(23, "status", StringType(), required=False),
                
                # Additional fields
                NestedField(30, "tags", ListType(31, StringType(), element_required=True), required=False),
                NestedField(32, "maintenance_date", StringType(), required=False),  # ISO string
                NestedField(33, "metadata", MapType(34, StringType(), 35, StringType(), value_required=False), required=False),
                
                # Partitioning fields
                NestedField(40, "partition_device", StringType(), required=True),
                NestedField(41, "partition_year", IntegerType(), required=True),
                NestedField(42, "partition_month", IntegerType(), required=True),
                NestedField(43, "partition_day", IntegerType(), required=True),
                NestedField(44, "partition_hour", IntegerType(), required=True),
            ]
            
            # Add dynamic fields based on sample data
            field_id = 100
            if sample_data:
                for key, value in sample_data.items():
                    # Skip fields that are already in base schema
                    base_field_names = {f.name for f in base_fields}
                    if key in base_field_names:
                        continue
                    
                    # Infer field type
                    field_type = self._infer_field_type(value)
                    if field_type:
                        base_fields.append(NestedField(field_id, key, field_type, required=False))
                        field_id += 1
            
            schema = IcebergSchema(*base_fields)
            log.info(f"Created Iceberg schema with {len(base_fields)} fields")
            return schema
            
        except Exception as e:
            log.error(f"Error creating Iceberg schema: {str(e)}")
            raise
    
    def _infer_field_type(self, value: Any):
        """
        Infer Iceberg field type from Python value
        
        Args:
            value: Python value to infer type from
            
        Returns:
            Iceberg type or None if cannot infer
        """
        if isinstance(value, str):
            return StringType()
        elif isinstance(value, bool):
            return BooleanType()
        elif isinstance(value, int):
            return LongType()
        elif isinstance(value, float):
            return DoubleType()
        elif isinstance(value, list):
            if value and isinstance(value[0], str):
                return ListType(1, StringType(), element_required=False)
        elif isinstance(value, dict):
            return MapType(1, StringType(), 2, StringType(), value_required=False)
        
        return None  # Cannot infer type
    
    def _create_partition_spec(self) -> PartitionSpec:
        """
        Create partition specification for optimal query performance
        
        Returns:
            Partition specification
        """
        try:
            # Partition by device_id (bucket) and time (hour)
            partition_spec = PartitionSpec(
                PartitionField(
                    source_id=40,  # partition_device field ID
                    field_id=1000,
                    transform=BucketTransform(num_buckets=16),
                    name="device_bucket"
                ),
                PartitionField(
                    source_id=41,  # partition_year field ID  
                    field_id=1001,
                    transform=IdentityTransform(),
                    name="year"
                ),
                PartitionField(
                    source_id=42,  # partition_month field ID
                    field_id=1002,
                    transform=IdentityTransform(),
                    name="month"
                ),
                PartitionField(
                    source_id=43,  # partition_day field ID
                    field_id=1003,
                    transform=IdentityTransform(),
                    name="day"
                ),
                PartitionField(
                    source_id=44,  # partition_hour field ID
                    field_id=1004,
                    transform=IdentityTransform(),
                    name="hour"
                )
            )
            
            log.info("Created partition specification with device bucketing and time partitioning")
            return partition_spec
            
        except Exception as e:
            log.error(f"Error creating partition spec: {str(e)}")
            raise
    
    def _create_sort_order(self) -> SortOrder:
        """
        Create sort order for optimal data layout
        
        Returns:
            Sort order specification
        """
        try:
            sort_order = SortOrder(
                SortField(source_id=3, direction="asc", null_order="nulls-first"),  # timestamp
                SortField(source_id=1, direction="asc", null_order="nulls-first"),  # device_id
            )
            
            log.info("Created sort order for timestamp and device_id")
            return sort_order
            
        except Exception as e:
            log.error(f"Error creating sort order: {str(e)}")
            raise
    
    def ensure_table(self, table_name: str, sample_data: Dict[str, Any] = None):
        """
        Ensure table exists, create if it doesn't, evolve schema if needed
        
        Args:
            table_name: Name of the table
            sample_data: Sample data for schema inference
            
        Returns:
            Iceberg table object
        """
        try:
            full_table_name = f"{self.namespace}.{table_name}"
            
            # Check if table exists in cache
            if full_table_name in self.tables_cache:
                table = self.tables_cache[full_table_name]
                
                # Check if schema evolution is needed
                if sample_data:
                    self._evolve_schema_if_needed(table, sample_data)
                
                return table
            
            # Check if table exists in catalog
            if self.catalog.table_exists(full_table_name):
                log.info(f"Loading existing table: {full_table_name}")
                table = self.catalog.load_table(full_table_name)
                
                # Check if schema evolution is needed
                if sample_data:
                    self._evolve_schema_if_needed(table, sample_data)
                
            else:
                log.info(f"Creating new table: {full_table_name}")
                
                # Create schema
                schema = self._create_iot_schema(sample_data)
                
                # Create partition spec
                partition_spec = self._create_partition_spec()
                
                # Create sort order
                sort_order = self._create_sort_order()
                
                # Create table
                table = self.catalog.create_table(
                    identifier=full_table_name,
                    schema=schema,
                    partition_spec=partition_spec,
                    sort_order=sort_order,
                    properties={
                        "write.parquet.compression-codec": "snappy",
                        "write.metadata.delete-after-commit.enabled": "true",
                        "write.metadata.previous-versions-max": "5",
                        "format-version": "2",
                    }
                )
                
                log.info(f"Created table: {full_table_name} with {len(schema.fields)} fields")
            
            # Cache the table
            self.tables_cache[full_table_name] = table
            return table
            
        except Exception as e:
            log.error(f"Error ensuring table {table_name}: {str(e)}")
            raise
    
    def _evolve_schema_if_needed(self, table, sample_data: Dict[str, Any]):
        """
        Evolve table schema if new fields are detected in sample data
        
        Args:
            table: Iceberg table object
            sample_data: Sample data to check for new fields
        """
        try:
            current_schema = table.schema()
            current_field_names = {field.name for field in current_schema.fields}
            
            # Find new fields in sample data
            new_fields = []
            field_id = max(field.field_id for field in current_schema.fields) + 1
            
            for key, value in sample_data.items():
                if key not in current_field_names:
                    field_type = self._infer_field_type(value)
                    if field_type:
                        new_fields.append(NestedField(field_id, key, field_type, required=False))
                        field_id += 1
            
            # Add new fields if any
            if new_fields:
                log.info(f"Evolving schema to add {len(new_fields)} new fields: {[f.name for f in new_fields]}")
                
                with table.update_schema() as update:
                    for field in new_fields:
                        update.add_column(field.name, field.field_type, required=field.required)
                
                # Update cached table
                full_table_name = f"{self.namespace}.{table.name()}"
                self.tables_cache[full_table_name] = table
                
        except Exception as e:
            log.error(f"Error evolving schema: {str(e)}")
            # Don't raise - continue with existing schema
    
    def write_batch(self, table_name: str, records: List[Dict[str, Any]]):
        """
        Write a batch of records to Iceberg table
        
        Args:
            table_name: Name of the table
            records: List of records to write
        """
        try:
            if not records:
                return
            
            # Ensure table exists (with schema evolution)
            table = self.ensure_table(table_name, sample_data=records[0])
            
            # Convert records to pandas DataFrame
            df = pd.DataFrame(records)
            
            # Handle nested fields and type conversions
            df = self._prepare_dataframe_for_iceberg(df)
            
            # Convert to PyArrow table
            arrow_table = pa.Table.from_pandas(df)
            
            # Write to Iceberg
            table.append(arrow_table)
            
            log.info(f"Successfully wrote {len(records)} records to table {table_name}")
            
        except Exception as e:
            log.error(f"Error writing batch to table {table_name}: {str(e)}")
            raise
    
    def _prepare_dataframe_for_iceberg(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Prepare pandas DataFrame for Iceberg writing
        
        Args:
            df: Input DataFrame
            
        Returns:
            Prepared DataFrame
        """
        try:
            # Handle timestamp columns
            timestamp_columns = ['timestamp', 'event_time', 'processing_time']
            for col in timestamp_columns:
                if col in df.columns:
                    df[col] = pd.to_datetime(df[col], utc=True)
            
            # Handle JSON string columns (convert to proper types)
            if 'location' in df.columns:
                # If location is a string, parse it
                if df['location'].dtype == 'object' and isinstance(df['location'].iloc[0], str):
                    df['location'] = df['location'].apply(json.loads)
            
            if 'metadata' in df.columns:
                # Ensure metadata is a dictionary
                if df['metadata'].dtype == 'object' and isinstance(df['metadata'].iloc[0], str):
                    df['metadata'] = df['metadata'].apply(json.loads)
            
            # Handle list columns
            if 'tags' in df.columns:
                # Ensure tags is a list
                df['tags'] = df['tags'].apply(lambda x: x if isinstance(x, list) else [])
            
            # Fill NaN values appropriately
            df = df.fillna({
                'battery_level': None,
                'signal_strength': None,
                'firmware_version': None,
                'status': 'UNKNOWN',
                'maintenance_date': None,
            })
            
            return df
            
        except Exception as e:
            log.error(f"Error preparing DataFrame for Iceberg: {str(e)}")
            raise
    
    def read_table(self, table_name: str, filter_expr=None, limit: Optional[int] = None) -> pd.DataFrame:
        """
        Read data from Iceberg table
        
        Args:
            table_name: Name of the table
            filter_expr: Optional filter expression
            limit: Optional limit on number of records
            
        Returns:
            Pandas DataFrame with results
        """
        try:
            full_table_name = f"{self.namespace}.{table_name}"
            
            if not self.catalog.table_exists(full_table_name):
                log.warning(f"Table does not exist: {full_table_name}")
                return pd.DataFrame()
            
            table = self.catalog.load_table(full_table_name)
            
            # Create scan
            scan = table.scan()
            
            # Apply filter if provided
            if filter_expr:
                scan = scan.filter(filter_expr)
            
            # Apply limit if provided
            if limit:
                scan = scan.limit(limit)
            
            # Convert to pandas
            arrow_table = scan.to_arrow()
            df = arrow_table.to_pandas()
            
            log.info(f"Read {len(df)} records from table {table_name}")
            return df
            
        except Exception as e:
            log.error(f"Error reading from table {table_name}: {str(e)}")
            raise
    
    def get_table_info(self, table_name: str) -> Dict[str, Any]:
        """
        Get information about a table
        
        Args:
            table_name: Name of the table
            
        Returns:
            Dictionary with table information
        """
        try:
            full_table_name = f"{self.namespace}.{table_name}"
            
            if not self.catalog.table_exists(full_table_name):
                return {"exists": False}
            
            table = self.catalog.load_table(full_table_name)
            schema = table.schema()
            
            return {
                "exists": True,
                "name": table_name,
                "schema_fields": len(schema.fields),
                "field_names": [field.name for field in schema.fields],
                "location": table.location(),
                "properties": table.properties,
                "partition_spec": str(table.spec()),
            }
            
        except Exception as e:
            log.error(f"Error getting table info for {table_name}: {str(e)}")
            return {"exists": False, "error": str(e)}
    
    def list_tables(self) -> List[str]:
        """
        List all tables in the namespace
        
        Returns:
            List of table names
        """
        try:
            identifiers = self.catalog.list_tables(self.namespace)
            table_names = [identifier[-1] for identifier in identifiers]  # Get just the table name
            log.info(f"Found {len(table_names)} tables in namespace {self.namespace}")
            return table_names
        except Exception as e:
            log.error(f"Error listing tables: {str(e)}")
            return []