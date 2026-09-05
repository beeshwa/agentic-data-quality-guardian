# Streamlit Guide

## Application: DQ_GUARDIAN_APP

8-page interactive dashboard deployed in Snowflake Streamlit.

## Deployment

1. Upload `streamlit/streamlit_app.py` to `@DQ_GUARDIAN.STREAMLIT.STREAMLIT_STAGE/`
2. The Streamlit object is created by the master SQL
3. Access via Snowsight: Streamlit Apps > DQ_GUARDIAN_APP

## Pages

### 1. Data Health Dashboard
KPI cards (score, tables, checks, pass/fail), table health grid, bar chart.
Sources: `V_OVERALL_HEALTH`, `V_TABLE_HEALTH_DASHBOARD`

### 2. Profiling Explorer
Table selector, row/column metrics, column stats, distribution viewer.
Sources: `TABLE_PROFILES`, `COLUMN_PROFILES`, `DISTRIBUTION_SNAPSHOTS`

### 3. Check Catalog
25 checks with category filter, severity, weight, AI-enhanced flag.
Source: `DQ_CHECK_LIBRARY`

### 4. Run History & Results
Run list, run selector, per-check results, failed record samples.
Sources: `DQ_RUN_LOG`, `V_CHECK_SUMMARY`, `DQ_FAILED_RECORDS`

### 5. AI Insights
Dataset profiles and failure explanations with expandable details.
Source: `AI_ANALYSIS_CACHE`

### 6. Remediation Center
Pending remediations with safety badges, recommendation text, history.
Sources: `V_PENDING_REMEDIATIONS`, `V_REMEDIATION_HISTORY`

### 7. Natural Language Query
Text input calls `SP_AI_NATURAL_LANGUAGE_QUERY`. Shows generated SQL and results.

### 8. Configuration
Monitored tables, active assignments, thresholds, task status. Read-only.
