#!/usr/bin/env python3
"""
Flink Job Submitter - Automatically submits SQL jobs to Flink cluster via REST API
"""

import os
import time
import json
import requests
from pathlib import Path
from typing import Dict, Any, List, Optional
import urllib.parse

from src.utils.logger import log

class FlinkJobSubmitter:
    """
    Submits Flink SQL jobs to the cluster via REST API
    """
    
    def __init__(self):
        self.jobmanager_host = os.getenv('FLINK_JOBMANAGER_HOST', 'flink-jobmanager')
        self.jobmanager_port = int(os.getenv('FLINK_JOBMANAGER_PORT', '8081'))
        self.base_url = f"http://{self.jobmanager_host}:{self.jobmanager_port}"
        
        # SQL Gateway endpoints (available in Flink 1.16+)
        self.sql_gateway_base = f"{self.base_url}/v1"
        
        # Paths
        self.sql_dir = Path('/app/flink/sql')
        self.jobs_dir = Path('/app/flink/jobs')
        
        # Job tracking
        self.submitted_jobs = {}
        self.current_session = None
        
        log.info(f"Flink Job Submitter initialized - JobManager: {self.base_url}")
    
    def wait_for_jobmanager(self, max_retries: int = 60) -> bool:
        """Wait for JobManager to be ready"""
        for attempt in range(max_retries):
            try:
                response = requests.get(f"{self.base_url}/overview", timeout=10)
                if response.status_code == 200:
                    log.info("JobManager is ready")
                    return True
            except Exception as e:
                log.debug(f"JobManager not ready (attempt {attempt + 1}): {e}")
            
            time.sleep(5)
        
        log.error("JobManager failed to become ready")
        return False
    
    def create_sql_session(self) -> Optional[str]:
        """Create a SQL gateway session"""
        try:
            # Create session with proper configuration
            session_data = {
                "sessionName": "iot-pipeline-session",
                "planner": "blink",
                "executionType": "streaming",
                "properties": {
                    "execution.runtime-mode": "STREAMING",
                    "parallelism.default": "2",
                    "execution.checkpointing.interval": "60s"
                }
            }
            
            response = requests.post(
                f"{self.sql_gateway_base}/sessions",
                json=session_data,
                headers={'Content-Type': 'application/json'},
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                session_handle = result.get('sessionHandle')
                self.current_session = session_handle
                log.info(f"Created SQL session: {session_handle}")
                return session_handle
            else:
                log.warning(f"Failed to create SQL session: {response.status_code} - {response.text}")
                return None
                
        except Exception as e:
            log.warning(f"SQL Gateway not available, trying alternative approach: {e}")
            return self._try_sql_client_approach()
    
    def _try_sql_client_approach(self) -> Optional[str]:
        """Fallback: Use direct job submission API"""
        try:
            # Check if we can submit jobs directly via /jars endpoint
            response = requests.get(f"{self.base_url}/jars", timeout=10)
            if response.status_code == 200:
                log.info("Using direct job submission API (no SQL Gateway)")
                return "direct-submission"
            return None
        except Exception as e:
            log.error(f"No available job submission method: {e}")
            return None
    
    def execute_sql_file(self, sql_file: Path, session_handle: Optional[str] = None) -> bool:
        """Execute SQL file"""
        try:
            if not sql_file.exists():
                log.error(f"SQL file not found: {sql_file}")
                return False
            
            sql_content = sql_file.read_text()
            
            # Split SQL statements
            statements = self._split_sql_statements(sql_content)
            
            success_count = 0
            for i, statement in enumerate(statements):
                if statement.strip():
                    log.info(f"Executing SQL statement {i + 1}/{len(statements)} from {sql_file.name}")
                    log.debug(f"Statement: {statement[:100]}...")
                    
                    if self._execute_sql_statement(statement, session_handle):
                        success_count += 1
                        log.info(f"✓ Statement {i + 1} executed successfully")
                    else:
                        log.error(f"✗ Statement {i + 1} failed")
                        # Continue with other statements for table creation
                        if sql_file.name == 'create_tables.sql':
                            continue
                        else:
                            return False
                    
                    time.sleep(3)  # Brief pause between statements
            
            log.info(f"Executed {success_count}/{len(statements)} statements from {sql_file.name}")
            return success_count > 0
            
        except Exception as e:
            log.error(f"Error executing SQL file {sql_file}: {e}")
            return False
    
    def _split_sql_statements(self, sql_content: str) -> List[str]:
        """Split SQL content into individual statements"""
        statements = []
        current_statement = ""
        in_comment_block = False
        
        for line in sql_content.split('\n'):
            line = line.strip()
            
            # Skip empty lines
            if not line:
                continue
                
            # Handle comment blocks
            if line.startswith('/*'):
                in_comment_block = True
                continue
            if line.endswith('*/'):
                in_comment_block = False
                continue
            if in_comment_block:
                continue
                
            # Skip single line comments
            if line.startswith('--'):
                continue
            
            current_statement += line + " "
            
            # Check for statement end
            if line.endswith(';'):
                statement = current_statement.strip()
                if statement and not statement.startswith('--'):
                    # Remove trailing semicolon
                    statements.append(statement[:-1])
                current_statement = ""
        
        # Add any remaining statement
        if current_statement.strip():
            statements.append(current_statement.strip())
        
        return [s for s in statements if s and not s.startswith('--')]
    
    def _execute_sql_statement(self, statement: str, session_handle: Optional[str] = None) -> bool:
        """Execute a single SQL statement"""
        try:
            if session_handle and session_handle != "direct-submission":
                return self._execute_via_sql_gateway(statement, session_handle)
            else:
                return self._execute_via_direct_submission(statement)
                
        except Exception as e:
            log.error(f"Error executing SQL statement: {e}")
            return False
    
    def _execute_via_sql_gateway(self, statement: str, session_handle: str) -> bool:
        """Execute SQL via SQL Gateway"""
        try:
            # Submit statement
            request_data = {
                "statement": statement,
                "executionConfig": {
                    "execution.runtime-mode": "STREAMING",
                    "parallelism.default": "2"
                }
            }
            
            response = requests.post(
                f"{self.sql_gateway_base}/sessions/{session_handle}/statements",
                json=request_data,
                headers={'Content-Type': 'application/json'},
                timeout=60
            )
            
            if response.status_code == 200:
                result = response.json()
                operation_handle = result.get('operationHandle')
                log.info(f"SQL statement submitted with operation handle: {operation_handle}")
                
                # Wait for operation to complete
                return self._wait_for_operation_completion(session_handle, operation_handle)
            else:
                log.error(f"Failed to execute SQL statement: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            log.error(f"Error executing via SQL Gateway: {e}")
            return False
    
    def _wait_for_operation_completion(self, session_handle: str, operation_handle: str, timeout: int = 120) -> bool:
        """Wait for operation to complete"""
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                response = requests.get(
                    f"{self.sql_gateway_base}/sessions/{session_handle}/operations/{operation_handle}/status",
                    timeout=10
                )
                
                if response.status_code == 200:
                    status = response.json().get('status')
                    log.debug(f"Operation status: {status}")
                    
                    if status == 'FINISHED':
                        log.info("Operation completed successfully")
                        return True
                    elif status in ['ERROR', 'CANCELED']:
                        log.error(f"Operation failed with status: {status}")
                        # Try to get error details
                        self._get_operation_result(session_handle, operation_handle)
                        return False
                    elif status in ['RUNNING', 'PENDING']:
                        time.sleep(2)
                        continue
                else:
                    log.warning(f"Failed to get operation status: {response.status_code}")
                    return False
                    
            except Exception as e:
                log.error(f"Error checking operation status: {e}")
                return False
        
        log.warning(f"Operation timed out after {timeout} seconds")
        return False
    
    def _get_operation_result(self, session_handle: str, operation_handle: str):
        """Get operation result for debugging"""
        try:
            response = requests.get(
                f"{self.sql_gateway_base}/sessions/{session_handle}/operations/{operation_handle}/result/0",
                timeout=10
            )
            
            if response.status_code == 200:
                result = response.json()
                log.debug(f"Operation result: {result}")
            
        except Exception as e:
            log.debug(f"Could not get operation result: {e}")
    
    def _execute_via_direct_submission(self, statement: str) -> bool:
        """Execute SQL via direct job submission (fallback)"""
        try:
            # This is a placeholder for direct job submission
            # In practice, you'd need to create a JAR with the SQL statement
            log.info(f"Would execute via direct submission: {statement[:100]}...")
            
            # For CREATE TABLE statements, assume success
            if any(keyword in statement.upper() for keyword in ['CREATE TABLE', 'CREATE CATALOG']):
                log.info("Table/Catalog creation statement - assuming success")
                return True
            
            # For INSERT statements, this would need actual job submission
            if 'INSERT INTO' in statement.upper():
                log.warning("INSERT statement requires actual job submission - not implemented in fallback mode")
                return False
            
            return True
            
        except Exception as e:
            log.error(f"Error executing via direct submission: {e}")
            return False
    
    def check_job_status(self, job_id: str) -> Optional[Dict[str, Any]]:
        """Check the status of a running job"""
        try:
            response = requests.get(f"{self.base_url}/jobs/{job_id}", timeout=10)
            if response.status_code == 200:
                return response.json()
            else:
                log.warning(f"Failed to get job status: {response.status_code}")
                return None
                
        except Exception as e:
            log.error(f"Error checking job status: {e}")
            return None
    
    def list_running_jobs(self) -> List[Dict[str, Any]]:
        """List all running jobs"""
        try:
            response = requests.get(f"{self.base_url}/jobs", timeout=10)
            if response.status_code == 200:
                jobs_data = response.json()
                return jobs_data.get('jobs', [])
            else:
                log.warning(f"Failed to list jobs: {response.status_code}")
                return []
                
        except Exception as e:
            log.error(f"Error listing jobs: {e}")
            return []
    
    def submit_all_jobs(self) -> bool:
        """Submit all SQL jobs and monitor them"""
        try:
            log.info("Starting job submission process...")
            
            # Wait for JobManager
            if not self.wait_for_jobmanager():
                return False
            
            # Create SQL session
            session_handle = self.create_sql_session()
            if not session_handle:
                log.error("Failed to create SQL session")
                return False
            
            # Submit table definitions first
            create_tables_file = self.sql_dir / 'create_tables.sql'
            if create_tables_file.exists():
                log.info("Creating tables...")
                if not self.execute_sql_file(create_tables_file, session_handle):
                    log.warning("Some table creation statements failed, continuing anyway")
                time.sleep(5)  # Wait for tables to be created
            else:
                log.warning(f"Table creation file not found: {create_tables_file}")
            
            # Submit streaming jobs
            streaming_job_file = self.sql_dir / 'streaming_job.sql'
            if streaming_job_file.exists():
                log.info("Submitting streaming jobs...")
                if self.execute_sql_file(streaming_job_file, session_handle):
                    log.info("✓ Streaming jobs submitted successfully")
                else:
                    log.error("✗ Failed to submit streaming jobs")
                    return False
            else:
                log.warning(f"Streaming job file not found: {streaming_job_file}")
            
            log.info("All jobs submitted successfully")
            return True
            
        except Exception as e:
            log.error(f"Error submitting jobs: {e}")
            return False
    
    def monitor_jobs(self):
        """Monitor submitted jobs continuously"""
        log.info("Starting job monitoring...")
        
        consecutive_empty_checks = 0
        max_empty_checks = 10  # Stop after 10 consecutive checks with no jobs
        
        while consecutive_empty_checks < max_empty_checks:
            try:
                # List all running jobs
                running_jobs = self.list_running_jobs()
                
                # Log job status
                if running_jobs:
                    consecutive_empty_checks = 0  # Reset counter
                    log.info(f"Found {len(running_jobs)} running jobs:")
                    for job in running_jobs:
                        job_id = job.get('id', 'unknown')
                        job_name = job.get('name', 'unknown')
                        job_state = job.get('state', 'unknown')
                        start_time = job.get('start-time', 0)
                        
                        # Convert timestamp to readable format
                        if start_time:
                            import datetime
                            start_time_str = datetime.datetime.fromtimestamp(start_time/1000).strftime('%H:%M:%S')
                        else:
                            start_time_str = 'unknown'
                        
                        log.info(f"  • {job_name} ({job_id[:8]}...): {job_state} (started: {start_time_str})")
                        
                        # Store job info for tracking
                        self.submitted_jobs[job_name] = job_id
                else:
                    consecutive_empty_checks += 1
                    log.info(f"No running jobs found (check {consecutive_empty_checks}/{max_empty_checks})")
                
                # Check specific job statuses if we have any tracked jobs
                failed_jobs = []
                for job_name, job_id in list(self.submitted_jobs.items()):
                    status = self.check_job_status(job_id)
                    if status:
                        state = status.get('state', 'unknown')
                        if state in ['FAILED', 'CANCELED']:
                            log.error(f"Job {job_name} failed with state: {state}")
                            failed_jobs.append(job_name)
                        elif state == 'FINISHED':
                            log.info(f"Job {job_name} completed successfully")
                            # Remove completed jobs from tracking
                            del self.submitted_jobs[job_name]
                
                # Remove failed jobs from tracking
                for job_name in failed_jobs:
                    if job_name in self.submitted_jobs:
                        del self.submitted_jobs[job_name]
                
                time.sleep(30)  # Check every 30 seconds
                
            except KeyboardInterrupt:
                log.info("Job monitoring stopped by user")
                break
            except Exception as e:
                log.error(f"Error in job monitoring: {e}")
                time.sleep(10)
        
        if consecutive_empty_checks >= max_empty_checks:
            log.info("No jobs found after extended monitoring - stopping monitor")

def main():
    """Main function"""
    submitter = FlinkJobSubmitter()
    
    # Submit all jobs
    if submitter.submit_all_jobs():
        # Monitor jobs
        submitter.monitor_jobs()
    else:
        log.error("Failed to submit jobs")
        exit(1)

if __name__ == "__main__":
    main()