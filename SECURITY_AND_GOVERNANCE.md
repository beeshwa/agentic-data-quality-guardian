# Security & Governance

## Design Principles

1. All procedures use `EXECUTE AS CALLER`
2. All tasks created `SUSPENDED`
3. Remediation never auto-executed from UI
4. Full audit trail for all AI actions
5. Default to blocking when in doubt

## SP_AI_APPLY_SAFE_FIX: 7-Layer Defense

| Layer | Check | Blocks |
|---|---|---|
| 1 | Type validation | Non-recommendation records |
| 2 | Safety classification | Anything except SAFE_TO_AUTOMATE |
| 3 | SQL extraction | Malformed AI responses |
| 4 | Destructive keywords | DROP, TRUNCATE, ALTER, GRANT, REVOKE, CREATE, DELETE FROM |
| 5 | DML-only enforcement | Non-UPDATE/INSERT/MERGE statements |
| 6 | Idempotency | Already-applied recommendations |
| 7 | Audit logging | Records every execution attempt |

## SP_AI_NATURAL_LANGUAGE_QUERY: 5-Layer Defense

| Layer | Check |
|---|---|
| 1 | Must start with SELECT or WITH |
| 2 | 15 blocked keywords (INSERT, UPDATE, DELETE, DROP, etc.) |
| 3 | Single statement only (no semicolons) |
| 4 | Approved object whitelist (11 objects) |
| 5 | 50-row result limit |

## Audit Trail

| Action | Location |
|---|---|
| DQ check execution | `DQ_RUN_LOG` |
| Check results | `DQ_CHECK_RESULTS` |
| Failed records | `DQ_FAILED_RECORDS` |
| AI analysis | `AI_ANALYSIS_CACHE` |
| Applied fixes | `REMEDIATION_AUDIT` |
| Approval decisions | `APPROVAL_QUEUE` |

## Streams for Monitoring

All 4 streams provide CDC-style change detection for downstream consumers.
