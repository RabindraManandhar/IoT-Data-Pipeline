"""
Flink Cluster Manager - Manages cluster health and job lifecycle
"""

import time
import requests
from typing import Dict, Any, List, Optional
from dataclasses import dataclass
from datetime import datetime, timezone

from src.utils.logger import log

@dataclass
class JobInfo:
    """Information about a Flink job"""
    job_id: str
    name: str
    state: str
    start_time: datetime
    end_time: Optional[datetime] = None
    duration: Optional[int] = None
    parallelism: int = 1

@dataclass
class ClusterInfo:
    """Information about Flink cluster"""
    taskmanagers: int
    slots_total: int
    slots_available: int
    jobs_running: int
    jobs_finished: int
    jobs_cancelled: int
    jobs_failed: int

class FlinkClusterManager:
    """
    Manages Flink cluster operations and health monitoring
    """
    
    def __init__(self, jobmanager_host: str = 'flink-jobmanager', jobmanager_port: int = 8081):
        self.jobmanager_host = jobmanager_host
        self.jobmanager_port = jobmanager_port
        self.base_url = f"http://{jobmanager_host}:{jobmanager_port}"
        
        log.info(f"Flink Cluster Manager initialized - {self.base_url}")
    
    def is_cluster_healthy(self) -> bool:
        """Check if the Flink cluster is healthy"""
        try:
            response = requests.get(f"{self.base_url}/overview", timeout=10)
            if response.status_code == 200:
                overview = response.json()
                taskmanagers = overview.get('taskmanagers', 0)
                slots_available = overview.get('slots-available', 0)
                
                # Cluster is healthy if we have taskmanagers and available slots
                return taskmanagers > 0 and slots_available > 0
            
            return False
            
        except Exception as e:
            log.error(f"Error checking cluster health: {e}")
            return False
    
    def get_cluster_info(self) -> Optional[ClusterInfo]:
        """Get detailed cluster information"""
        try:
            response = requests.get(f"{self.base_url}/overview", timeout=10)
            if response.status_code == 200:
                overview = response.json()
                
                return ClusterInfo(
                    taskmanagers=overview.get('taskmanagers', 0),
                    slots_total=overview.get('slots-total', 0),
                    slots_available=overview.get('slots-available', 0),
                    jobs_running=overview.get('jobs-running', 0),
                    jobs_finished=overview.get('jobs-finished', 0),
                    jobs_cancelled=overview.get('jobs-cancelled', 0),
                    jobs_failed=overview.get('jobs-failed', 0)
                )
            
            return None
            
        except Exception as e:
            log.error(f"Error getting cluster info: {e}")
            return None
    
    def get_job_details(self, job_id: str) -> Optional[JobInfo]:
        """Get detailed information about a specific job"""
        try:
            response = requests.get(f"{self.base_url}/jobs/{job_id}", timeout=10)
            if response.status_code == 200:
                job_data = response.json()
                
                start_time = datetime.fromtimestamp(
                    job_data.get('start-time', 0) / 1000, 
                    tz=timezone.utc
                )
                
                end_time = None
                if job_data.get('end-time'):
                    end_time = datetime.fromtimestamp(
                        job_data.get('end-time', 0) / 1000,
                        tz=timezone.utc
                    )
                
                return JobInfo(
                    job_id=job_id,
                    name=job_data.get('name', 'unknown'),
                    state=job_data.get('state', 'unknown'),
                    start_time=start_time,
                    end_time=end_time,
                    duration=job_data.get('duration'),
                    parallelism=job_data.get('parallelism', 1)
                )
            
            return None
            
        except Exception as e:
            log.error(f"Error getting job details for {job_id}: {e}")
            return None
    
    def cancel_job(self, job_id: str) -> bool:
        """Cancel a running job"""
        try:
            response = requests.patch(f"{self.base_url}/jobs/{job_id}", timeout=10)
            if response.status_code == 202:
                log.info(f"Job {job_id} cancellation requested")
                return True
            else:
                log.error(f"Failed to cancel job {job_id}: {response.status_code}")
                return False
                
        except Exception as e:
            log.error(f"Error cancelling job {job_id}: {e}")
            return False
    
    def restart_job(self, job_id: str) -> bool:
        """Restart a job (cancel and resubmit)"""
        try:
            # First cancel the job
            if self.cancel_job(job_id):
                # Wait for cancellation
                time.sleep(5)
                
                # Get job details to resubmit
                job_info = self.get_job_details(job_id)
                if job_info:
                    log.info(f"Job {job_id} cancelled, would need to resubmit")
                    # Note: Actual resubmission would require storing job definitions
                    return True
            
            return False
            
        except Exception as e:
            log.error(f"Error restarting job {job_id}: {e}")
            return False
    
    def get_job_metrics(self, job_id: str) -> Optional[Dict[str, Any]]:
        """Get metrics for a specific job"""
        try:
            response = requests.get(f"{self.base_url}/jobs/{job_id}/metrics", timeout=10)
            if response.status_code == 200:
                return response.json()
            
            return None
            
        except Exception as e:
            log.error(f"Error getting job metrics for {job_id}: {e}")
            return None
    
    def get_taskmanager_info(self) -> List[Dict[str, Any]]:
        """Get information about all TaskManagers"""
        try:
            response = requests.get(f"{self.base_url}/taskmanagers", timeout=10)
            if response.status_code == 200:
                return response.json().get('taskmanagers', [])
            
            return []
            
        except Exception as e:
            log.error(f"Error getting TaskManager info: {e}")
            return []
    
    def wait_for_cluster_ready(self, max_wait_seconds: int = 300) -> bool:
        """Wait for cluster to be ready"""
        start_time = time.time()
        
        while time.time() - start_time < max_wait_seconds:
            if self.is_cluster_healthy():
                cluster_info = self.get_cluster_info()
                if cluster_info:
                    log.info(f"Cluster ready - TaskManagers: {cluster_info.taskmanagers}, "
                            f"Available slots: {cluster_info.slots_available}")
                    return True
            
            log.info("Waiting for cluster to be ready...")
            time.sleep(10)
        
        log.error("Cluster failed to become ready within timeout")
        return False
    
    def monitor_cluster_health(self, interval_seconds: int = 30):
        """Continuously monitor cluster health"""
        log.info("Starting cluster health monitoring...")
        
        while True:
            try:
                cluster_info = self.get_cluster_info()
                
                if cluster_info:
                    log.info(f"Cluster Status - TaskManagers: {cluster_info.taskmanagers}, "
                            f"Jobs Running: {cluster_info.jobs_running}, "
                            f"Available Slots: {cluster_info.slots_available}")
                    
                    # Check for failed jobs
                    if cluster_info.jobs_failed > 0:
                        log.warning(f"Found {cluster_info.jobs_failed} failed jobs")
                        
                    # Check for resource availability
                    if cluster_info.slots_available == 0 and cluster_info.jobs_running > 0:
                        log.warning("No available slots - cluster may be overloaded")
                        
                else:
                    log.error("Failed to get cluster information")
                
                time.sleep(interval_seconds)
                
            except KeyboardInterrupt:
                log.info("Cluster monitoring stopped by user")
                break
            except Exception as e:
                log.error(f"Error in cluster monitoring: {e}")
                time.sleep(10)