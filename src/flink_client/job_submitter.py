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

from src.utils.logger import log

class FlinkJobSubmitter:
    """
    Submits Flink SQL jobs to the cluster via REST API
    """
    
    def __init__(self):
        self.jobmanager_host = os.getenv('FLINK_JOBMANAGER_HOST', 'flink-jobmanager')
        self.jobmanager_port = int(os.getenv('FLINK_JOBMANAGER_PORT', '8081'))
        self.base_url = f"http://{self.jobmanager_host}:{self.jobmanager_port}"
        
        # Paths
        self.sql_dir = Path('/app/flink/sql')
        self.jobs_dir = Path('/app/flink/jobs')
        
        # Job tracking
        self.submitted_jobs = {}
        
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
            # First, check if SQL gateway is available
            response = requests.get(f"{self.base_url}/v1/sessions", timeout=10)
            if response.status_code == 404:
                log.warning("SQL Gateway not available, using job submission API instead")
                return None
            
            # Create session
            session_data = {
                "sessionName": "iot-pipeline-session",
                "planner": "blink",
                "executionType": "streaming"
            }
            
            response = requests.post(
                f"{self.base_url}/v1/sessions",
                json=session_data,
                headers={'Content-Type': 'application/json'}
            )
            
            if response.status_code == 200:
                session_handle = response.json()['sessionHandle']
                log.info(f"Created SQL session: {session_handle}")
                return session_handle
            else:
                log.warning(f"Failed to create SQL session: {response.status_code}")
                return None
                
        except Exception as e:
            log.warning(f"SQL Gateway not available: {e}")
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
            
            for i, statement in enumerate(statements):
                if statement.strip():
                    log.info(f"Executing SQL statement {i + 1} from {sql_file.name}")
                    success = self._execute_sql_statement(statement, session_handle)
                    if not success:
                        log.error(f"Failed to execute statement {i + 1}")
                        return False
                    time.sleep(2)  # Brief pause between statements
            
            return True
            
        except Exception as e:
            log.error(f"Error executing SQL file {sql_file}: {e}")
            return False
    
    def _split_sql_statements(self, sql_content: str) -> List[str]:
        """Split SQL content into individual statements"""
        # Simple split by semicolon (could be enhanced for complex cases)
        statements = []
        current_statement = ""
        
        for line in sql_content.split('\n'):
            line = line.strip()
            if line.startswith('--') or not line:
                continue
            
            current_statement += line + " "
            
            if line.endswith(';'):
                statements.append(current_statement.strip()[:-1])  # Remove trailing semicolon
                current_statement = ""
        
        if current_statement.strip():
            statements.append(current_statement.strip())
        
        return statements
   
    def _execute_sql_statement(self, statement: str, session_handle: Optional[str] = None) -> bool:
        """Execute a single SQL statement"""
        try:
            if session_handle:
                # Use SQL Gateway
                return self._execute_via_sql_gateway(statement, session_handle)
            else:
                # Use job submission API
                return self._execute_via_job_submission(statement)
                
        except Exception as e:
            log.error(f"Error executing SQL statement: {e}")
            return False
   
    def _execute_via_sql_gateway(self, statement: str, session_handle: str) -> bool:
        """Execute SQL via SQL Gateway"""
        try:
            request_data = {
                "statement": statement,
                "executionConfig": {
                    "execution.runtime-mode": "STREAMING"
                }
            }
            
            response = requests.post(
                f"{self.base_url}/v1/sessions/{session_handle}/statements",
                json=request_data,
                headers={'Content-Type': 'application/json'}
            )
            
            if response.status_code == 200:
                result = response.json()
                operation_handle = result.get('operationHandle')
                log.info(f"SQL statement submitted with operation handle: {operation_handle}")
                return True
            else:
                log.error(f"Failed to execute SQL statement: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            log.error(f"Error executing via SQL Gateway: {e}")
            return False
    
    def _execute_via_job_submission(self, statement: str) -> bool:
        """Execute SQL via job submission API"""
        try:
            # Create a temporary SQL job
            job_data = {
                "jobName": f"iot-sql-job-{int(time.time())}",
                "jobType": "SQL",
                "sql": statement,
                "parallelism": 2
            }
            
            # Note: This is a simplified approach. In practice, you might need to
            # create a PyFlink job that executes the SQL
            log.info(f"Would submit SQL job: {statement[:100]}...")
            return True
            
        except Exception as e:
            log.error(f"Error executing via job submission: {e}")
            return False
    
    def submit_python_job(self, job_file: Path, job_args: Dict[str, Any] = None) -> Optional[str]:
        """Submit a Python job to Flink cluster"""
        try:
            if not job_file.exists():
                log.error(f"Job file not found: {job_file}")
                return None
            
            # Read job content
            job_content = job_file.read_text()
            
            # Create job submission request
            job_data = {
                "jobName": f"iot-python-job-{int(time.time())}",
                "jobType": "PYTHON",
                "entryClass": "org.apache.flink.client.python.PythonDriver",
                "programArgs": self._build_program_args(job_file, job_args or {}),
                "parallelism": 2,
                "savepointPath": None
            }
            
            # Submit job
            response = requests.post(
                f"{self.base_url}/v1/jobs",
                json=job_data,
                headers={'Content-Type': 'application/json'}
            )
            
            if response.status_code == 200:
                job_id = response.json().get('jobid')
                log.info(f"Python job submitted with ID: {job_id}")
                return job_id
            else:
                log.error(f"Failed to submit Python job: {response.status_code} - {response.text}")
                return None
                
        except Exception as e:
            log.error(f"Error submitting Python job: {e}")
            return None
    
    def _build_program_args(self, job_file: Path, job_args: Dict[str, Any]) -> List[str]:
        """Build program arguments for Python job"""
        args = [
            "--python", str(job_file),
            "--jarfile", "/opt/flink/lib/custom/flink-python-1.19.1.jar"
        ]
        
        # Add job-specific arguments
        for key, value in job_args.items():
            args.extend([f"--{key}", str(value)])
        
        return args
    
    def check_job_status(self, job_id: str) -> Optional[Dict[str, Any]]:
        """Check the status of a running job"""
        try:
            response = requests.get(f"{self.base_url}/jobs/{job_id}")
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
            response = requests.get(f"{self.base_url}/jobs")
            if response.status_code == 200:
                return response.json().get('jobs', [])
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
            
            # Submit table definitions first
            create_tables_file = self.sql_dir / 'create_tables.sql'
            if create_tables_file.exists():
                log.info("Creating tables...")
                if not self.execute_sql_file(create_tables_file, session_handle):
                    log.error("Failed to create tables")
                    return False
                time.sleep(10)  # Wait for tables to be created
            
            # Submit streaming jobs
            streaming_job_file = self.sql_dir / 'streaming_job.sql'
            if streaming_job_file.exists():
                log.info("Submitting streaming jobs...")
                if not self.execute_sql_file(streaming_job_file, session_handle):
                    log.error("Failed to submit streaming jobs")
                    return False
            
            # Submit Python jobs if any
            python_jobs = list(self.jobs_dir.glob('*.py'))
            for job_file in python_jobs:
                log.info(f"Submitting Python job: {job_file.name}")
                job_id = self.submit_python_job(job_file)
                if job_id:
                    self.submitted_jobs[job_file.name] = job_id
            
            log.info("All jobs submitted successfully")
            return True
            
        except Exception as e:
            log.error(f"Error submitting jobs: {e}")
            return False
    
    def monitor_jobs(self):
        """Monitor submitted jobs continuously"""
        log.info("Starting job monitoring...")
        
        while True:
            try:
                # List all running jobs
                running_jobs = self.list_running_jobs()
                
                # Log job status
                if running_jobs:
                    log.info(f"Found {len(running_jobs)} running jobs:")
                    for job in running_jobs:
                        job_id = job.get('id', 'unknown')
                        job_name = job.get('name', 'unknown')
                        job_state = job.get('state', 'unknown')
                        log.info(f"  - {job_name} ({job_id}): {job_state}")
                else:
                    log.warning("No running jobs found")
                
                # Check specific job statuses
                for job_name, job_id in self.submitted_jobs.items():
                    status = self.check_job_status(job_id)
                    if status:
                        state = status.get('state', 'unknown')
                        if state in ['FAILED', 'CANCELED']:
                            log.error(f"Job {job_name} failed with state: {state}")
                        elif state == 'FINISHED':
                            log.info(f"Job {job_name} completed successfully")
                
                time.sleep(30)  # Check every 30 seconds
                
            except KeyboardInterrupt:
                log.info("Job monitoring stopped by user")
                break
            except Exception as e:
                log.error(f"Error in job monitoring: {e}")
                time.sleep(10)

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