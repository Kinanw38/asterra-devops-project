# Engineering Design Abstract & Half-Pager

## Overview & Executive Summary
This project delivers a completely reproducible Cloud and DevOps framework built specifically to satisfy the strict architecture guidelines of the ASTERRA DevOps Technical Assignment. The goal is to ingest GeoJSON data automatically while serving public and private geographic platforms securely under strict Least Privilege access controls.

## Strategic Architectural Decisions

### 1. VPC Segmentation & Private Ingestion Isolation
Instead of exposing the database or core components to the web, all analytical workflows are locked inside an isolated private subnet. RDP connectivity to the GIS environment is strictly limited via configurable Terraform security variables to enforce IP white-listing.

### 2. State Management & Dynamic Backends
To guarantee continuous reproducibility across any region, a dedicated Bash controller orchestrates state generation dynamically. This effectively abstracts the backend bucket initialization phase away from the core structural manifest files, preventing chicken-and-egg deployment traps.

### 3. Engineered Polling vs. Event Hook Latency
In choosing a design for the ingestion daemon, a resilient polling loop pattern was prioritized over direct S3-to-EC2 API notification routing hooks. This choice minimizes infrastructure configuration overhead, bypasses complex cross-account access configurations, and runs stably within AWS Free Tier limitations.

## Retrospective: What Failed & Engineering Lessons Learned

### PostGIS Extension Conundrum
Initially, attempting to initiate the `postgis` spatial extension directly through a standard Terraform remote bootstrap script caused intermittent connection timeouts. This occurred because the RDS database cluster instance was still initializing network components after reporting a "Ready" state.

**Resolution:** The database initialization responsibility was shifted directly to the application layer. By wrapping the extension initialization check (`CREATE EXTENSION IF NOT EXISTS postgis;`) inside the Python application startup flow, the application gracefully handles transient database readiness lag using resilient runtime validation loops.

### Secrets Recycling Lockout
During early pipeline iterations, destroying and recreating the environment in rapid succession triggered AWS Secrets Manager API throttles, as deleted secrets are normally held in a recovery queue for a minimum of 7 days.

**Resolution:** Configured the `aws_secretsmanager_secret` parameter with `recovery_window_in_days = 0` to bypass the recovery queue, enabling clean, error-free execution of rapid setup and teardown cycles.