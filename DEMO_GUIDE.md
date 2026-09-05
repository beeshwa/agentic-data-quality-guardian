# Demo Guide

5-10 minute hackathon walkthrough.

## Pre-Demo

- Master SQL executed, synthetic data loaded
- At least one DQ run completed
- Health scores calculated
- AI explanations generated
- Streamlit app accessible

## Script

### 1. The Problem (1 min)
> "Data quality issues are discovered too late. DQ Guardian catches them early, explains them with AI, and can fix them safely."

Open **Data Health Dashboard**. Show overall score and table health.

### 2. The Engine (2 min)
Open **Check Catalog**. Show 25 checks, filter by CRITICAL. Highlight metadata-driven design.

Open **Profiling Explorer**. Select CUSTOMERS. Show column stats and distributions.

### 3. AI Intelligence (2-3 min)
Open **Run History**. Select a run, show failed checks and sample records.

Open **AI Insights**. Show failure explanations — highlight how AI identifies root causes.

### 4. Safe Remediation (2-3 min)
Open **Remediation Center**. Show safety badges. Explain SAFE vs HUMAN REVIEW distinction.

From SQL worksheet:
```sql
CALL DQ_GUARDIAN.CORTEX_AI.SP_AI_RECOMMEND_REMEDIATION('<CHECK_RESULT_ID>');
CALL DQ_GUARDIAN.CORTEX_AI.SP_AI_APPLY_SAFE_FIX('<RECOMMENDATION_ID>');
-- Shows SKIPPED for REQUIRES_HUMAN_REVIEW — safety working
```

### 5. Natural Language (1 min)
Open **Natural Language Query**. Ask: "Which tables have the lowest health scores?"

Show generated SQL and results. Emphasize the 5-layer safety validation.

### 6. Closing (30 sec)
> "100% Snowflake-native. 25 checks, Cortex AI, 7-layer safety, full audit trail."

## Backup: SQL-Only Demo

```sql
CALL DQ_GUARDIAN.CHECK_RESULTS.SP_RUN_ALL_CHECKS();
SELECT * FROM DQ_GUARDIAN.CHECK_RESULTS.V_OVERALL_HEALTH;
CALL DQ_GUARDIAN.CORTEX_AI.SP_AI_NATURAL_LANGUAGE_QUERY('Which table has the most failures?');
```
