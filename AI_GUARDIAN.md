# AI Guardian — Cortex AI Architecture

All AI calls use `SNOWFLAKE.CORTEX.COMPLETE('llama3.3-70b', prompt)`.

## Procedures

| Procedure | Purpose | Input | Output |
|---|---|---|---|
| `SP_AI_PROFILE_DATASET` | Business-readable dataset summary | Table FQN | AI profile in AI_ANALYSIS_CACHE |
| `SP_AI_EXPLAIN_FAILURES` | Root cause explanations per failed check | RUN_ID | Explanations in AI_ANALYSIS_CACHE |
| `SP_AI_RECOMMEND_REMEDIATION` | Fix recommendations with safety classification | CHECK_RESULT_ID | Recommendation in AI_ANALYSIS_CACHE |
| `SP_AI_APPLY_SAFE_FIX` | Executes SAFE_TO_AUTOMATE fixes only | RECOMMENDATION_ID | Fix applied + audit row |
| `SP_AI_RERUN_AND_SCORE` | Reruns checks, compares health scores | RUN_ID | Before/after comparison |
| `SP_AI_NATURAL_LANGUAGE_QUERY` | NL to SQL with safety validation | Question text | Query results (max 50 rows) |

## Safety Classifications

- **SAFE_TO_AUTOMATE** — Low-risk fix, can be auto-applied
- **REQUIRES_HUMAN_REVIEW** — Needs human approval before execution
- **UNSAFE** — Must not be auto-applied

## Prompt Design

- Prompts include structured context (table name, check details, metrics, sample failed records)
- Responses are parsed for SQL extraction (```sql blocks)
- All AI responses cached in `AI_ANALYSIS_CACHE` keyed by type, RUN_ID, CHECK_ID
- Idempotent: delete-before-insert prevents duplicate analysis records
