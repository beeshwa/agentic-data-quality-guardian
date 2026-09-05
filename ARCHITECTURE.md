# Architecture

## System Overview

DQ Guardian is a single-database Snowflake-native application. All compute, storage, orchestration, and AI inference run inside Snowflake.

```mermaid
graph TB
    subgraph "DQ_GUARDIAN Database"
        CONFIG["CONFIG<br/>Check Library, Assignments, Thresholds"]
        SYNTH["SYNTHETIC_DATA<br/>9 Demo Tables"]
        PROF["PROFILING<br/>Profiles, Distributions, Snapshots"]
        CR["CHECK_RESULTS<br/>Run Logs, Results, Health Scores"]
        REM["REMEDIATION<br/>Recommendations, Approvals, Audit"]
        CAI["CORTEX_AI<br/>Analysis Cache, Prompt Templates"]
        SL["STREAMLIT<br/>DQ_GUARDIAN_APP"]
    end
    CONFIG -->|definitions| CR
    SYNTH -->|data| PROF
    SYNTH -->|data| CR
    PROF -->|profiles| CAI
    CR -->|failures| CAI
    CAI -->|recommendations| REM
    CR --> SL
    REM --> SL
    CAI --> SL
```

## Task DAG

```mermaid
graph TD
    T1["TASK_PROFILE_TABLES<br/>60 min schedule"] --> T2["TASK_RUN_DQ_CHECKS"]
    T2 --> T3["TASK_CALCULATE_HEALTH"]
    T2 --> T4["TASK_AI_EXPLAIN_FAILURES"]
```

All tasks created SUSPENDED.

## Data Flow

```mermaid
sequenceDiagram
    participant Config as CONFIG
    participant Engine as SP_RUN_DQ_CHECKS
    participant Source as Source Tables
    participant Results as CHECK_RESULTS
    participant AI as Cortex AI
    participant Remed as REMEDIATION

    Engine->>Config: Read check definitions
    Engine->>Source: Execute templated SQL
    Engine->>Results: Write results + failed records
    Results->>AI: SP_AI_EXPLAIN_FAILURES
    AI->>Remed: SP_AI_RECOMMEND_REMEDIATION
    Remed->>Remed: SP_AI_APPLY_SAFE_FIX (SAFE only)
```

## Metadata-Driven Engine

The core design: **no IF/ELSE branching**. Each of 25 check types stores a SQL template in `DQ_CHECK_LIBRARY`. At runtime, `SP_RUN_DQ_CHECKS` substitutes `{{placeholders}}` from `DQ_CHECK_ASSIGNMENTS.PARAMS_JSON` using a custom `safeReplace()` function (avoids JavaScript `$` regex issues), then executes the SQL dynamically.

## Stream Architecture

| Stream | Source | Purpose |
|---|---|---|
| `STREAM_DQ_CHECK_RESULTS` | `DQ_CHECK_RESULTS` | New check results |
| `STREAM_SCHEMA_SNAPSHOTS` | `SCHEMA_SNAPSHOTS` | Schema drift triggers |
| `STREAM_AI_RECOMMENDATIONS` | `AI_RECOMMENDATIONS` | New AI recommendations |
| `STREAM_REMEDIATION_AUDIT` | `REMEDIATION_AUDIT` | Remediation audit trail |
