# Deployment Guide

## Prerequisites

- Snowflake account with `ACCOUNTADMIN` role
- Snowflake Cortex AI enabled (`SNOWFLAKE.CORTEX.COMPLETE`)
- Warehouse (e.g., `COMPUTE_WH`)
- Streamlit in Snowflake enabled

## Step 1: Run the Master SQL

Execute `sql/Agentic Data Qualtity Guardian.sql` end-to-end in a Snowflake worksheet. The script creates all objects in dependency order:

1. Database and 7 schemas
2. CONFIG tables with 25 check definitions
3. Synthetic data tables with seed data
4. Profiling tables
5. Check result tables
6. UDFs
7. DQ engine procedures
8. Health scoring procedure
9. Dashboard views
10. Cortex AI tables and procedures
11. Remediation tables and views
12. Tasks (created SUSPENDED)
13. Streams

## Step 2: Deploy Streamlit

1. Upload `streamlit/streamlit_app.py` to the stage:
   ```
   snow stage copy streamlit_app.py @DQ_GUARDIAN.STREAMLIT.STREAMLIT_STAGE/ --overwrite
   ```
   Or use Snowsight UI: Data > Databases > DQ_GUARDIAN > STREAMLIT > Stages > STREAMLIT_STAGE > Upload.

2. The Streamlit object `DQ_GUARDIAN_APP` is created by the master SQL.

## Step 3: First Run

```sql
-- Run all DQ checks
CALL DQ_GUARDIAN.CHECK_RESULTS.SP_RUN_ALL_CHECKS();

-- Get a RUN_ID from the results
SELECT RUN_ID, TARGET_TABLE FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG ORDER BY RUN_START_TIME DESC;

-- Calculate health scores
CALL DQ_GUARDIAN.CHECK_RESULTS.SP_CALCULATE_HEALTH_SCORE('<RUN_ID>');

-- AI analysis
CALL DQ_GUARDIAN.CORTEX_AI.SP_AI_EXPLAIN_FAILURES('<RUN_ID>');

-- View dashboard
SELECT * FROM DQ_GUARDIAN.CHECK_RESULTS.V_OVERALL_HEALTH;
```

## Step 4: Activate Tasks (Optional)

```sql
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('DQ_GUARDIAN.CONFIG.TASK_PROFILE_TABLES');
```

## Validation

```sql
SELECT COUNT(*) FROM DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY;          -- 25
SELECT COUNT(*) FROM DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS;      -- 42
SELECT COUNT(*) FROM DQ_GUARDIAN.SYNTHETIC_DATA.CUSTOMERS;         -- 15
SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.3-70b', 'test');          -- Cortex works
```
