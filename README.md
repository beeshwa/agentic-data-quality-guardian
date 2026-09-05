# Agentic Data Quality Guardian

> **CoCoQuest 2026 Hackathon** — A Snowflake-native, AI-powered data quality platform that combines a metadata-driven check engine with Cortex AI intelligence and an interactive Streamlit dashboard.

---

## What It Does

DQ Guardian monitors your data estate through **25 data quality checks** spanning 10 dimensions — all driven by metadata configuration, not hard-coded logic. When checks fail, **Cortex AI explains why**, recommends remediations, and can safely auto-apply fixes classified as low-risk.

### Key Capabilities

| Capability | Description |
|---|---|
| **Metadata-Driven Engine** | 25 check types executed via template substitution — zero IF/ELSE branching |
| **Automated Profiling** | Table, column, and distribution profiling with schema drift detection |
| **Cortex AI Intelligence** | AI-generated failure explanations, remediation recommendations, dataset profiles, and natural language querying |
| **7-Layer Safe Remediation** | Automated fixes with type validation, destructive keyword blocking, DML-only enforcement, and full audit trails |
| **8-Page Streamlit Dashboard** | Interactive UI for health monitoring, profiling, AI insights, remediation, and configuration |
| **Task Pipeline** | Chained tasks for continuous data quality monitoring |

---

## Architecture

```
DQ_GUARDIAN Database
├── CONFIG           — Check library (25 checks), assignments, thresholds
├── SYNTHETIC_DATA   — 9 demo tables with intentional defects
├── PROFILING        — Table/column profiles, distributions, schema snapshots
├── CHECK_RESULTS    — Run logs, check results, failed records, health scores
├── REMEDIATION      — AI recommendations, approval queue, audit trail
├── CORTEX_AI        — Analysis cache, prompt templates
└── STREAMLIT        — Dashboard app + stage
```

## Object Count

| Type | Count |
|---|---|
| Database | 1 |
| Schemas | 7 |
| Tables | 23 |
| Views | 5 |
| Stored Procedures | 11 |
| UDFs | 3 |
| Tasks | 4 |
| Streams | 4 |
| Streamlit App | 1 |

---

## Quick Start

```sql
-- 1. Run the master deployment SQL end-to-end
-- 2. Profile tables and run checks
CALL DQ_GUARDIAN.CHECK_RESULTS.SP_RUN_ALL_CHECKS();

-- 3. Let AI explain failures
CALL DQ_GUARDIAN.CORTEX_AI.SP_AI_EXPLAIN_FAILURES('<run_id>');

-- 4. Open the Streamlit dashboard
```

> See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for full setup instructions and [DEMO_GUIDE.md](DEMO_GUIDE.md) for the hackathon walkthrough.

---

## Documentation

| Document | Description |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture with diagrams |
| [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) | Step-by-step fresh deployment |
| [OBJECT_CATALOG.md](OBJECT_CATALOG.md) | Complete object inventory |
| [DQ_CHECK_CATALOG.md](DQ_CHECK_CATALOG.md) | All 25 data quality checks |
| [AI_GUARDIAN.md](AI_GUARDIAN.md) | Cortex AI architecture and procedures |
| [REMEDIATION_WORKFLOW.md](REMEDIATION_WORKFLOW.md) | Remediation lifecycle |
| [STREAMLIT_GUIDE.md](STREAMLIT_GUIDE.md) | Dashboard pages and usage |
| [DEMO_GUIDE.md](DEMO_GUIDE.md) | Hackathon demo script |
| [SECURITY_AND_GOVERNANCE.md](SECURITY_AND_GOVERNANCE.md) | Security controls |

---

## Tech Stack

- **Snowflake** — Database, compute, and orchestration
- **JavaScript Stored Procedures** — Core engine logic with `safeReplace()` template substitution
- **Snowflake Cortex AI** — `SNOWFLAKE.CORTEX.COMPLETE` with `llama3.3-70b`
- **Streamlit in Snowflake** — Interactive 8-page dashboard
- **SQL / Snowpark** — Data transformations and UDFs

---

## Project Structure

```
agentic-data-quality-guardian/
├── README.md
├── ARCHITECTURE.md
├── DEPLOYMENT_GUIDE.md
├── OBJECT_CATALOG.md
├── DQ_CHECK_CATALOG.md
├── AI_GUARDIAN.md
├── REMEDIATION_WORKFLOW.md
├── STREAMLIT_GUIDE.md
├── DEMO_GUIDE.md
├── SECURITY_AND_GOVERNANCE.md
├── sql/
│   └── Agentic Data Qualtity Guardian.sql
└── streamlit/
    └── streamlit_app.py
```

---

## Known Limitations

- `DQ_HEALTH_SCORES` is a regular table (not Dynamic Table) — intentional for procedure compatibility with `SP_CALCULATE_HEALTH_SCORE`
- `SP_RUN_ALL_CHECKS` runs all configured tables per invocation
- Cortex AI responses are non-deterministic
- Streamlit deployment requires manual file upload to `STREAMLIT_STAGE`
- `DQ_SCHEDULES` and `DQ_SLA_DEFINITIONS` tables are reserved for future use

---

## License

Built for CoCoQuest 2026.
