# Object Catalog

## Summary

| Type | Count |
|---|---|
| Database | 1 |
| Schemas | 7 |
| Tables | 23 |
| Views | 5 |
| Procedures | 11 |
| UDFs | 3 |
| Tasks | 4 |
| Streams | 4 |
| Streamlit | 1 |
| Stage | 1 |

## CONFIG (5 Tables)

| Object | Purpose |
|---|---|
| `DQ_CHECK_LIBRARY` | 25 check definitions with SQL templates |
| `DQ_CHECK_ASSIGNMENTS` | Maps checks to tables/columns |
| `DQ_THRESHOLDS` | Warning/fail thresholds |
| `DQ_SCHEDULES` | Schedule config (reserved) |
| `DQ_SLA_DEFINITIONS` | SLA definitions (reserved) |

## SYNTHETIC_DATA (9 Tables)

CUSTOMERS, PRODUCTS, ORDERS, ORDER_ITEMS, EMPLOYEES, AUDIT_LOG, DAILY_AGGREGATES, FILE_INGESTION_LOG, DEFECT_CATALOG

## PROFILING (4 Tables, 2 Procedures)

| Object | Type | Purpose |
|---|---|---|
| `TABLE_PROFILES` | Table | Row counts per table |
| `COLUMN_PROFILES` | Table | Column-level statistics |
| `DISTRIBUTION_SNAPSHOTS` | Table | Value distributions |
| `SCHEMA_SNAPSHOTS` | Table | Schema baselines |
| `SP_PROFILE_TABLE` | Procedure | Profiles a table |
| `SP_DETECT_SCHEMA_DRIFT` | Procedure | Compares schema vs baseline |

## CHECK_RESULTS (4 Tables, 3 Views, 3 UDFs, 3 Procedures)

| Object | Type | Purpose |
|---|---|---|
| `DQ_RUN_LOG` | Table | Run metadata |
| `DQ_CHECK_RESULTS` | Table | Per-check results |
| `DQ_FAILED_RECORDS` | Table | Failed record samples |
| `DQ_HEALTH_SCORES` | Table | Weighted health scores |
| `V_CHECK_SUMMARY` | View | Check details with run info |
| `V_TABLE_HEALTH_DASHBOARD` | View | Table health for dashboard |
| `V_OVERALL_HEALTH` | View | Aggregate health |
| `FN_SCORE_CHECK` | UDF | Weighted score calculation |
| `FN_DETECT_OUTLIER` | UDF | Z-score outlier detection |
| `FN_VALIDATE_REGEX` | UDF | Pattern validation |
| `SP_RUN_DQ_CHECKS` | Procedure | Core DQ engine |
| `SP_RUN_ALL_CHECKS` | Procedure | Orchestrator |
| `SP_CALCULATE_HEALTH_SCORE` | Procedure | Health scoring |

## CORTEX_AI (2 Tables, 6 Procedures)

| Object | Type | Purpose |
|---|---|---|
| `AI_ANALYSIS_CACHE` | Table | Cached AI responses |
| `PROMPT_TEMPLATES` | Table | Reusable prompts |
| `SP_AI_PROFILE_DATASET` | Procedure | AI dataset profile |
| `SP_AI_EXPLAIN_FAILURES` | Procedure | AI failure explanations |
| `SP_AI_RECOMMEND_REMEDIATION` | Procedure | AI remediation recommendations |
| `SP_AI_APPLY_SAFE_FIX` | Procedure | Safe fix execution |
| `SP_AI_RERUN_AND_SCORE` | Procedure | Rerun + score comparison |
| `SP_AI_NATURAL_LANGUAGE_QUERY` | Procedure | NL to SQL |

## REMEDIATION (3 Tables, 2 Views)

| Object | Type | Purpose |
|---|---|---|
| `AI_RECOMMENDATIONS` | Table | AI recommendations |
| `REMEDIATION_AUDIT` | Table | Fix audit trail |
| `APPROVAL_QUEUE` | Table | Human approval queue |
| `V_PENDING_REMEDIATIONS` | View | Pending items |
| `V_REMEDIATION_HISTORY` | View | Historical actions |

## Tasks (4, all SUSPENDED)

| Task | Predecessor | Calls |
|---|---|---|
| `TASK_PROFILE_TABLES` | Root (hourly) | SP_PROFILE_TABLE |
| `TASK_RUN_DQ_CHECKS` | TASK_PROFILE_TABLES | SP_RUN_ALL_CHECKS |
| `TASK_CALCULATE_HEALTH` | TASK_RUN_DQ_CHECKS | SP_CALCULATE_HEALTH_SCORE |
| `TASK_AI_EXPLAIN_FAILURES` | TASK_RUN_DQ_CHECKS | SP_AI_EXPLAIN_FAILURES |

## Streams (4)

| Stream | Source |
|---|---|
| `STREAM_DQ_CHECK_RESULTS` | DQ_CHECK_RESULTS |
| `STREAM_SCHEMA_SNAPSHOTS` | SCHEMA_SNAPSHOTS |
| `STREAM_AI_RECOMMENDATIONS` | AI_RECOMMENDATIONS |
| `STREAM_REMEDIATION_AUDIT` | REMEDIATION_AUDIT |
