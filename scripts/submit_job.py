#!/usr/bin/env python3
"""
Standalone script to submit Flink jobs
"""

import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from src.flink_client.job_submitter import FlinkJobSubmitter

def main():
    """Submit jobs to Flink cluster"""
    submitter = FlinkJobSubmitter()
    
    if submitter.submit_all_jobs():
        print("Jobs submitted successfully!")
        
        # Optionally monitor jobs
        if len(sys.argv) > 1 and sys.argv[1] == "--monitor":
            submitter.monitor_jobs()
    else:
        print("Failed to submit jobs")
        sys.exit(1)

if __name__ == "__main__":
    main()