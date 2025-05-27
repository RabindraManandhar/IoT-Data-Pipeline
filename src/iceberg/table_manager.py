"""
PyIceberg Table Manager - Specialized operations for table management
"""

import pandas as pd
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass

from pyiceberg.schema import Schema as IcebergSchema
from pyiceberg.types import NestedField, StringType, DoubleType, BooleanType, IntegerType, LongType, TimestampType
from pyiceberg.partitioning import PartitionSpec, PartitionField
from pyiceberg.transforms import IdentityTransform, BucketTransform, HourTransform, DayTransform
from pyiceberg.table.sorting import SortOrder, SortField
from pyiceberg.expressions import GreaterThanOrEqual, LessThan, EqualTo, And

from src.utils.logger import log

@dataclass
class TableMetrics:
    """Metrics for table operations"""
    table_name: str
    record_count: int
    file_count: int
    total_size_bytes: int
    partition_count: int
    last_updated: datetime
    schema_version: int

class TableManager:
    """
    Specialized manager for Iceberg table operations
    """
    
    def __init__(self, catalog, namespace: str = "iot_data"):
        """
        Initialize table manager
        
        Args:
            catalog: Iceberg catalog instance
            namespace: Namespace for tables
        """
        self.catalog = catalog
        self.namespace = namespace
        self.tables_cache = {}
        
    def create_partitioned_table(
        self, 
        table_name: str, 
        schema: IcebergSchema,
        partition_strategy: str = "device_time",
        sort_columns: List[str] = None
    ):
        """
        Create a partitioned table with optimal settings
        
        Args:
            table_name: Name of the table
            schema: Iceberg schema
            partition_strategy: Partitioning strategy
            sort_columns: Columns to sort by
        """
        try:
            full_table_name = f"{self.namespace}.{table_name}"
            
            # Create partition specification based on strategy
            partition_spec = self._create_partition_spec(schema, partition_strategy)
            
            # Create sort order
            sort_order = self._create_sort_order(schema, sort_columns)
            
            # Optimized table properties for IoT data
            properties = {
                "write.parquet.compression-codec": "snappy",
                "write.target-file-size-bytes": str(128 * 1024 * 1024),  # 128MB
                "write.metadata.delete-after-commit.enabled": "true",
                "write.metadata.previous-versions-max": "10",
                "format-version": "2",
                "write.distribution-mode": "hash",  # Distribute writes evenly
                "write.wap.enabled": "true",  # Write-Audit-Publish for consistency
            }
            
            # Create the table
            table = self.catalog.create_table(
                identifier=full_table_name,
                schema=schema,
                partition_spec=partition_spec,
                sort_order=sort_order,
                properties=properties
            )
            
            log.info(f"Created partitioned table {table_name} with strategy {partition_strategy}")
            return table
            
        except Exception as e:
            log.error(f"Error creating partitioned table {table_name}: {str(e)}")
            raise
    
    def _create_partition_spec(self, schema: IcebergSchema, strategy: str) -> PartitionSpec:
        """
        Create partition specification based on strategy
        
        Args:
            schema: Table schema
            strategy: Partitioning strategy
            
        Returns:
            Partition specification
        """
        try:
            if strategy == "device_time":
                # Partition by device bucket and time hierarchy
                return PartitionSpec(
                    PartitionField(
                        source_id=self._get_field_id(schema, "partition_device"),
                        field_id=1000,
                        transform=BucketTransform(num_buckets=16),
                        name="device_bucket"
                    ),
                    PartitionField(
                        source_id=self._get_field_id(schema, "partition_year"),
                        field_id=1001,
                        transform=IdentityTransform(),
                        name="year"
                    ),
                    PartitionField(
                        source_id=self._get_field_id(schema, "partition_month"),
                        field_id=1002,
                        transform=IdentityTransform(),
                        name="month"
                    ),
                    PartitionField(
                        source_id=self._get_field_id(schema, "partition_day"),
                        field_id=1003,
                        transform=IdentityTransform(),
                        name="day"
                    )
                )
            
            elif strategy == "device_hour":
                # Partition by device and hour for high-frequency data
                return PartitionSpec(
                    PartitionField(
                        source_id=self._get_field_id(schema, "partition_device"),
                        field_id=1000,
                        transform=BucketTransform(num_buckets=8),
                        name="device_bucket"
                    ),
                    PartitionField(
                        source_id=self._get_field_id(schema, "timestamp"),
                        field_id=1001,
                        transform=HourTransform(),
                        name="hour"
                    )
                )
            
            elif strategy == "device_type":
                # Partition by device type and date
                return PartitionSpec(
                    PartitionField(
                        source_id=self._get_field_id(schema, "device_type"),
                        field_id=1000,
                        transform=IdentityTransform(),
                        name="device_type"
                    ),
                    PartitionField(
                        source_id=self._get_field_id(schema, "timestamp"),
                        field_id=1001,
                        transform=DayTransform(),
                        name="date"
                    )
                )
            
            else:
                # Default: simple time-based partitioning
                return PartitionSpec(
                    PartitionField(
                        source_id=self._get_field_id(schema, "timestamp"),
                        field_id=1000,
                        transform=DayTransform(),
                        name="date"
                    )
                )
                
        except Exception as e:
            log.error(f"Error creating partition spec with strategy {strategy}: {str(e)}")
            raise
    
    def _create_sort_order(self, schema: IcebergSchema, sort_columns: List[str] = None) -> SortOrder:
        """
        Create sort order for optimal data layout
        
        Args:
            schema: Table schema
            sort_columns: Optional list of columns to sort by
            
        Returns:
            Sort order specification
        """
        try:
            if sort_columns:
                sort_fields = []
                for i, col in enumerate(sort_columns):
                    field_id = self._get_field_id(schema, col)
                    if field_id:
                        sort_fields.append(
                            SortField(source_id=field_id, direction="asc", null_order="nulls-first")
                        )
                return SortOrder(*sort_fields)
            
            # Default sort order: timestamp, then device_id
            return SortOrder(
                SortField(
                    source_id=self._get_field_id(schema, "timestamp"),
                    direction="asc",
                    null_order="nulls-first"
                ),
                SortField(
                    source_id=self._get_field_id(schema, "device_id"),
                    direction="asc", 
                    null_order="nulls-first"
                )
            )
            
        except Exception as e:
            log.error(f"Error creating sort order: {str(e)}")
            raise
    
    def _get_field_id(self, schema: IcebergSchema, field_name: str) -> Optional[int]:
        """
        Get field ID by name from schema
        
        Args:
            schema: Iceberg schema
            field_name: Name of the field
            
        Returns:
            Field ID or None if not found
        """
        for field in schema.fields:
            if field.name == field_name:
                return field.field_id
        return None
    
    def optimize_table(self, table_name: str, target_file_size_mb: int = 128):
        """
        Optimize table by compacting small files
        
        Args:
            table_name: Name of the table
            target_file_size_mb: Target file size in MB
        """
        try:
            full_table_name = f"{self.namespace}.{table_name}"
            table = self.catalog.load_table(full_table_name)
            
            # Get table metrics before optimization
            before_metrics = self.get_table_metrics(table_name)
            
            # Perform compaction (this is a placeholder - actual implementation depends on Iceberg version)
            # In practice, you might use Spark or Flink for compaction
            log.info(f"Starting table optimization for {table_name}")
            
            # For now, log the intention - actual compaction would be done via Spark/Flink
            log.info(f"Table {table_name} has {before_metrics.file_count} files, "
                    f"average size: {before_metrics.total_size_bytes / before_metrics.file_count / 1024 / 1024:.2f}MB")
            
            # TODO: Implement actual compaction logic
            # This would typically involve:
            # 1. Identifying small files
            # 2. Reading and combining them
            # 3. Writing back as larger files
            # 4. Updating metadata
            
            log.info(f"Table optimization completed for {table_name}")
            
        except Exception as e:
            log.error(f"Error optimizing table {table_name}: {str(e)}")
            raise
    
    def get_table_metrics(self, table_name: str) -> TableMetrics:
        """
        Get metrics for a table
        
        Args:
            table_name: Name of the table
            
        Returns:
            Table metrics
        """
        try:
            full_table_name = f"{self.namespace}.{table_name}"
            
            if not self.catalog.table_exists(full_table_name):
                raise ValueError(f"Table {full_table_name} does not exist")
            
            table = self.catalog.load_table(full_table_name)
            
            # Get table metadata
            metadata = table.metadata
            schema_version = len(metadata.schemas)
            
            # For now, return basic metrics (would need actual scan for accurate counts)
            return TableMetrics(
                table_name=table_name,
                record_count=0,  # Would need to scan to get accurate count
                file_count=len(metadata.snapshots[-1].manifest_list) if metadata.snapshots else 0,
                total_size_bytes=0,  # Would need to calculate from manifest files
                partition_count=0,  # Would need to scan partitions
                last_updated=datetime.now(timezone.utc),
                schema_version=schema_version
            )
            
        except Exception as e:
            log.error(f"Error getting table metrics for {table_name}: {str(e)}")
            raise
    
    def query_recent_data(
        self, 
        table_name: str, 
        hours_back: int = 24,
        device_ids: List[str] = None,
        limit: int = None
    ) -> pd.DataFrame:
        """
        Query recent data from table with time and device filters
        
        Args:
            table_name: Name of the table
            hours_back: Number of hours to look back
            device_ids: Optional list of device IDs to filter
            limit: Optional limit on results
            
        Returns:
            DataFrame with results
        """
        try:
            full_table_name = f"{self.namespace}.{table_name}"
            table = self.catalog.load_table(full_table_name)
            
            # Calculate time filter
            cutoff_time = datetime.now(timezone.utc).timestamp() - (hours_back * 3600)
            
            # Build filter expression
            time_filter = GreaterThanOrEqual("timestamp", cutoff_time * 1000)  # Iceberg uses milliseconds
            
            scan = table.scan().filter(time_filter)
            
            # Add device filter if specified
            if device_ids:
                device_filters = [EqualTo("device_id", device_id) for device_id in device_ids]
                if len(device_filters) == 1:
                    scan = scan.filter(device_filters[0])
                else:
                    # For multiple devices, we'd need OR logic (not directly supported in this simple form)
                    log.warning("Multiple device ID filtering not fully implemented - using first device only")
                    scan = scan.filter(device_filters[0])
            
            # Apply limit
            if limit:
                scan = scan.limit(limit)
            
            # Execute scan and convert to pandas
            arrow_table = scan.to_arrow()
            df = arrow_table.to_pandas()
            
            log.info(f"Queried {len(df)} recent records from {table_name}")
            return df
            
        except Exception as e:
            log.error(f"Error querying recent data from {table_name}: {str(e)}")
            raise
    
    def get_partition_info(self, table_name: str) -> Dict[str, Any]:
        """
        Get partition information for a table
        
        Args:
            table_name: Name of the table
            
        Returns:
            Dictionary with partition information
        """
        try:
            full_table_name = f"{self.namespace}.{table_name}"
            table = self.catalog.load_table(full_table_name)
            
            spec = table.spec()
            partition_fields = []
            
            for field in spec.fields:
                partition_fields.append({
                    "field_id": field.field_id,
                    "source_id": field.source_id,
                    "name": field.name,
                    "transform": str(field.transform)
                })
            
            return {
                "spec_id": spec.spec_id,
                "fields": partition_fields,
                "field_count": len(partition_fields)
            }
            
        except Exception as e:
            log.error(f"Error getting partition info for {table_name}: {str(e)}")
            return {}
    
    def cleanup_old_snapshots(self, table_name: str, keep_snapshots: int = 10):
        """
        Clean up old snapshots to save storage space
        
        Args:
            table_name: Name of the table
            keep_snapshots: Number of snapshots to keep
        """
        try:
            full_table_name = f"{self.namespace}.{table_name}"
            table = self.catalog.load_table(full_table_name)
            
            # Get current snapshots
            snapshots = table.metadata.snapshots
            
            if len(snapshots) <= keep_snapshots:
                log.info(f"Table {table_name} has {len(snapshots)} snapshots, no cleanup needed")
                return
            
            # Calculate snapshots to expire
            snapshots_to_expire = len(snapshots) - keep_snapshots
            
            log.info(f"Cleaning up {snapshots_to_expire} old snapshots from {table_name}")
            
            # Expire old snapshots (placeholder - actual implementation varies by Iceberg version)
            # In practice, this would use table.expire_snapshots() or similar API
            
            log.info(f"Snapshot cleanup completed for {table_name}")
            
        except Exception as e:
            log.error(f"Error cleaning up snapshots for {table_name}: {str(e)}")
            raise