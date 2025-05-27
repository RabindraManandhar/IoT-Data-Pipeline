"""
Monitoring and Metrics Utilities for IoT Data Pipeline
Provides health checks, metrics collection, and alerting capabilities
"""

import time
import json
import asyncio
import psutil
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional, Callable
from dataclasses import dataclass, asdict
from collections import defaultdict, deque

import requests
from confluent_kafka.admin import AdminClient

from src.utils.logger import log
from src.config.config import settings

@dataclass
class ServiceHealth:
    """Health status for a service"""
    service_name: str
    status: str  # healthy, unhealthy, unknown
    response_time_ms: float
    last_check: datetime
    error_message: Optional[str] = None
    additional_info: Dict[str, Any] = None

@dataclass
class MetricPoint:
    """Single metric data point"""
    name: str
    value: float
    timestamp: datetime
    tags: Dict[str, str] = None
    unit: str = None

@dataclass
class SystemMetrics:
    """System-level metrics"""
    cpu_percent: float
    memory_percent: float
    disk_percent: float
    network_bytes_sent: int
    network_bytes_recv: int
    timestamp: datetime

class HealthChecker:
    """
    Health checker for all pipeline services
    """
    
    def __init__(self):
        self.health_status = {}
        self.check_interval = settings.monitoring.health_check_interval_ms / 1000
        
    async def check_kafka_health(self) -> ServiceHealth:
        """Check Kafka cluster health"""
        start_time = time.time()
        try:
            admin_client = AdminClient({
                'bootstrap.servers': settings.kafka.bootstrap_servers,
                'request.timeout.ms': 10000
            })
            
            # List topics as a health check
            topics = admin_client.list_topics(timeout=10)
            response_time = (time.time() - start_time) * 1000
            
            return ServiceHealth(
                service_name="kafka",
                status="healthy",
                response_time_ms=response_time,
                last_check=datetime.now(timezone.utc),
                additional_info={
                    "topic_count": len(topics.topics),
                    "brokers": len(topics.brokers)
                }
            )
            
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return ServiceHealth(
                service_name="kafka",
                status="unhealthy",
                response_time_ms=response_time,
                last_check=datetime.now(timezone.utc),
                error_message=str(e)
            )
    
    async def check_schema_registry_health(self) -> ServiceHealth:
        """Check Schema Registry health"""
        start_time = time.time()
        try:
            response = requests.get(
                f"{settings.schema_registry.url}/subjects",
                timeout=10
            )
            response.raise_for_status()
            response_time = (time.time() - start_time) * 1000
            
            subjects = response.json()
            
            return ServiceHealth(
                service_name="schema_registry",
                status="healthy",
                response_time_ms=response_time,
                last_check=datetime.now(timezone.utc),
                additional_info={
                    "subject_count": len(subjects)
                }
            )
            
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return ServiceHealth(
                service_name="schema_registry",
                status="unhealthy",
                response_time_ms=response_time,
                last_check=datetime.now(timezone.utc),
                error_message=str(e)
            )
    
    async def check_flink_health(self) -> ServiceHealth:
        """Check Flink JobManager health"""
        start_time = time.time()
        try:
            flink_host = settings.flink.jobmanager.host
            flink_port = settings.flink.jobmanager.web_port
            
            response = requests.get(
                f"http://{flink_host}:{flink_port}/overview",
                timeout=10
            )
            response.raise_for_status()
            response_time = (time.time() - start_time) * 1000
            
            overview = response.json()
            
            return ServiceHealth(
                service_name="flink",
                status="healthy",
                response_time_ms=response_time,
                last_check=datetime.now(timezone.utc),
                additional_info={
                    "taskmanagers": overview.get("taskmanagers", 0),
                    "slots_total": overview.get("slots-total", 0),
                    "slots_available": overview.get("slots-available", 0),
                    "jobs_running": overview.get("jobs-running", 0)
                }
            )
            
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return ServiceHealth(
                service_name="flink",
                status="unhealthy",
                response_time_ms=response_time,
                last_check=datetime.now(timezone.utc),
                error_message=str(e)
            )
    
    async def check_minio_health(self) -> ServiceHealth:
        """Check MinIO health"""
        start_time = time.time()
        try:
            minio_endpoint = settings.minio.endpoint
            
            response = requests.get(
                f"{minio_endpoint}/minio/health/live",
                timeout=10
            )
            response.raise_for_status()
            response_time = (time.time() - start_time) * 1000
            
            return ServiceHealth(
                service_name="minio",
                status="healthy",
                response_time_ms=response_time,
                last_check=datetime.now(timezone.utc)
            )
            
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return ServiceHealth(
                service_name="minio",
                status="unhealthy",
                response_time_ms=response_time,
                last_check=datetime.now(timezone.utc),
                error_message=str(e)
            )
    
    async def check_postgres_health(self) -> ServiceHealth:
        """Check PostgreSQL health"""
        start_time = time.time()
        try:
            import psycopg2
            
            conn = psycopg2.connect(
                host=settings.postgres.host,
                port=settings.postgres.port,
                database=settings.postgres.database,
                user=settings.postgres.username,
                password=settings.postgres.password,
                connect_timeout=10
            )
            
            cur = conn.cursor()
            cur.execute("SELECT version();")
            version = cur.fetchone()[0]
            cur.close()
            conn.close()
            
            response_time = (time.time() - start_time) * 1000
            
            return ServiceHealth(
                service_name="postgres",
                status="healthy",
                response_time_ms=response_time,
                last_check=datetime.now(timezone.utc),
                additional_info={
                    "version": version[:50]  # Truncate long version string
                }
            )
            
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return ServiceHealth(
                service_name="postgres",
                status="unhealthy",
                response_time_ms=response_time,
                last_check=datetime.now(timezone.utc),
                error_message=str(e)
            )
    
    async def check_all_services(self) -> Dict[str, ServiceHealth]:
        """Check health of all services"""
        try:
            # Run all health checks concurrently
            health_checks = await asyncio.gather(
                self.check_kafka_health(),
                self.check_schema_registry_health(),
                self.check_flink_health(),
                self.check_minio_health(),
                self.check_postgres_health(),
                return_exceptions=True
            )
            
            # Organize results
            results = {}
            for health in health_checks:
                if isinstance(health, ServiceHealth):
                    results[health.service_name] = health
                elif isinstance(health, Exception):
                    log.error(f"Health check failed with exception: {str(health)}")
            
            self.health_status.update(results)
            return results
            
        except Exception as e:
            log.error(f"Error checking service health: {str(e)}")
            return {}

class MetricsCollector:
    """
    Collects and stores metrics from various sources
    """
    
    def __init__(self, max_points: int = 10000):
        self.metrics_buffer = deque(maxlen=max_points)
        self.metric_aggregates = defaultdict(list)
        self.collection_interval = settings.monitoring.metrics.interval_ms / 1000
        
    def add_metric(self, metric: MetricPoint):
        """Add a metric point to the buffer"""
        self.metrics_buffer.append(metric)
        
        # Also store in aggregates for analysis
        key = f"{metric.name}_{metric.tags.get('service', 'unknown') if metric.tags else 'unknown'}"
        self.metric_aggregates[key].append(metric.value)
        
        # Keep only recent values for aggregates
        if len(self.metric_aggregates[key]) > 1000:
            self.metric_aggregates[key] = self.metric_aggregates[key][-500:]
    
    def collect_system_metrics(self) -> SystemMetrics:
        """Collect system-level metrics"""
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            network = psutil.net_io_counters()
            
            system_metrics = SystemMetrics(
                cpu_percent=cpu_percent,
                memory_percent=memory.percent,
                disk_percent=disk.percent,
                network_bytes_sent=network.bytes_sent,
                network_bytes_recv=network.bytes_recv,
                timestamp=datetime.now(timezone.utc)
            )
            
            # Convert to metric points
            timestamp = system_metrics.timestamp
            base_tags = {"service": "system", "host": "localhost"}
            
            metrics = [
                MetricPoint("cpu_percent", cpu_percent, timestamp, base_tags, "percent"),
                MetricPoint("memory_percent", memory.percent, timestamp, base_tags, "percent"),
                MetricPoint("disk_percent", disk.percent, timestamp, base_tags, "percent"),
                MetricPoint("network_bytes_sent", network.bytes_sent, timestamp, base_tags, "bytes"),
                MetricPoint("network_bytes_recv", network.bytes_recv, timestamp, base_tags, "bytes"),
            ]
            
            for metric in metrics:
                self.add_metric(metric)
            
            return system_metrics
            
        except Exception as e:
            log.error(f"Error collecting system metrics: {str(e)}")
            return None
    
    def get_metric_summary(self, metric_name: str, service: str = None) -> Dict[str, float]:
        """Get summary statistics for a metric"""
        try:
            key = f"{metric_name}_{service or 'unknown'}"
            values = self.metric_aggregates.get(key, [])
            
            if not values:
                return {}
            
            return {
                "count": len(values),
                "min": min(values),
                "max": max(values),
                "avg": sum(values) / len(values),
                "recent": values[-1] if values else 0
            }
            
        except Exception as e:
            log.error(f"Error getting metric summary: {str(e)}")
            return {}

class AlertManager:
    """
    Manages alerts based on metrics and health status
    """
    
    def __init__(self):
        self.alert_callbacks: List[Callable] = []
        self.alert_history = deque(maxlen=1000)
        self.suppressed_alerts = set()
        
    def add_alert_callback(self, callback: Callable):
        """Add callback function for alert notifications"""
        self.alert_callbacks.append(callback)
    
    def check_kafka_lag_alert(self, metrics_collector: MetricsCollector):
        """Check for Kafka consumer lag alerts"""
        try:
            lag_summary = metrics_collector.get_metric_summary("kafka_lag", "consumer")
            if lag_summary and lag_summary.get("recent", 0) > settings.monitoring.alerts.kafka_lag_threshold:
                self._trigger_alert(
                    "kafka_lag_high",
                    f"Kafka consumer lag is {lag_summary['recent']}, threshold is {settings.monitoring.alerts.kafka_lag_threshold}",
                    severity="warning"
                )
        except Exception as e:
            log.error(f"Error checking Kafka lag alert: {str(e)}")
    
    def check_flink_job_alert(self, health_status: Dict[str, ServiceHealth]):
        """Check for Flink job alerts"""
        try:
            flink_health = health_status.get("flink")
            if flink_health and flink_health.status == "unhealthy":
                self._trigger_alert(
                    "flink_job_unhealthy",
                    f"Flink JobManager is unhealthy: {flink_health.error_message}",
                    severity="critical"
                )
        except Exception as e:
            log.error(f"Error checking Flink job alert: {str(e)}")
    
    def check_storage_alert(self, system_metrics: SystemMetrics):
        """Check for storage space alerts"""
        try:
            if system_metrics and system_metrics.disk_percent > 85:
                self._trigger_alert(
                    "disk_space_low",
                    f"Disk usage is {system_metrics.disk_percent}%, exceeding 85% threshold",
                    severity="warning"
                )
        except Exception as e:
            log.error(f"Error checking storage alert: {str(e)}")
    
    def _trigger_alert(self, alert_id: str, message: str, severity: str = "info"):
        """Trigger an alert"""
        try:
            # Check if alert is suppressed
            if alert_id in self.suppressed_alerts:
                return
            
            alert = {
                "id": alert_id,
                "message": message,
                "severity": severity,
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "service": "iot-pipeline"
            }
            
            # Add to history
            self.alert_history.append(alert)
            
            # Log the alert
            if severity == "critical":
                log.error(f"ALERT [{severity.upper()}]: {message}")
            elif severity == "warning":
                log.warning(f"ALERT [{severity.upper()}]: {message}")
            else:
                log.info(f"ALERT [{severity.upper()}]: {message}")
            
            # Call registered callbacks
            for callback in self.alert_callbacks:
                try:
                    callback(alert)
                except Exception as e:
                    log.error(f"Error in alert callback: {str(e)}")
            
            # Suppress similar alerts for 5 minutes
            self._suppress_alert(alert_id, duration_seconds=300)
            
        except Exception as e:
            log.error(f"Error triggering alert: {str(e)}")
    
    def _suppress_alert(self, alert_id: str, duration_seconds: int):
        """Suppress an alert for a specific duration"""
        self.suppressed_alerts.add(alert_id)
        
        # Remove suppression after duration (in a real implementation, use a scheduler)
        def remove_suppression():
            time.sleep(duration_seconds)
            self.suppressed_alerts.discard(alert_id)
        
        # In practice, you'd use asyncio.create_task or threading.Timer
        import threading
        threading.Timer(duration_seconds, remove_suppression).start()

class PipelineMonitor:
    """
    Main monitoring coordinator
    """
    
    def __init__(self):
        self.health_checker = HealthChecker()
        self.metrics_collector = MetricsCollector()
        self.alert_manager = AlertManager()
        self.running = False
        
        # Setup alert callbacks
        self.alert_manager.add_alert_callback(self._log_alert)
    
    def _log_alert(self, alert: Dict[str, Any]):
        """Default alert callback - just log to file"""
        try:
            alert_json = json.dumps(alert, indent=2)
            log.info(f"Alert triggered: {alert_json}")
        except Exception as e:
            log.error(f"Error logging alert: {str(e)}")
    
    async def start_monitoring(self):
        """Start the monitoring loop"""
        self.running = True
        log.info("Starting pipeline monitoring...")
        
        try:
            while self.running:
                # Collect health status
                health_status = await self.health_checker.check_all_services()
                
                # Collect system metrics
                system_metrics = self.metrics_collector.collect_system_metrics()
                
                # Check for alerts
                self.alert_manager.check_flink_job_alert(health_status)
                self.alert_manager.check_kafka_lag_alert(self.metrics_collector)
                if system_metrics:
                    self.alert_manager.check_storage_alert(system_metrics)
                
                # Log summary
                healthy_services = sum(1 for h in health_status.values() if h.status == "healthy")
                total_services = len(health_status)
                
                log.info(f"Health check: {healthy_services}/{total_services} services healthy")
                
                # Wait before next check
                await asyncio.sleep(self.health_checker.check_interval)
                
        except Exception as e:
            log.error(f"Error in monitoring loop: {str(e)}")
        finally:
            log.info("Pipeline monitoring stopped")
    
    def stop_monitoring(self):
        """Stop the monitoring loop"""
        self.running = False
        log.info("Stopping pipeline monitoring...")
    
    def get_status_report(self) -> Dict[str, Any]:
        """Get comprehensive status report"""
        try:
            return {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "health_status": {k: asdict(v) for k, v in self.health_checker.health_status.items()},
                "system_metrics": self.metrics_collector.collect_system_metrics(),
                "alert_count": len(self.alert_manager.alert_history),
                "recent_alerts": list(self.alert_manager.alert_history)[-5:]  # Last 5 alerts
            }
        except Exception as e:
            log.error(f"Error generating status report: {str(e)}")
            return {"error": str(e)}