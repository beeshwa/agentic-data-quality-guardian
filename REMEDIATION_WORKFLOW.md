# Remediation Workflow

## Lifecycle

```
DQ Failure → AI Explanation → AI Recommendation → Safety Classification
  ├── SAFE_TO_AUTOMATE → SP_AI_APPLY_SAFE_FIX → Audit → Revalidation
  └── REQUIRES_HUMAN_REVIEW → Approval Queue → Manual Review
```

## SP_AI_APPLY_SAFE_FIX: 7-Layer Defense

1. **Type validation** — Confirms recommendation exists and is REMEDIATION_RECOMMENDATION
2. **Safety classification** — Must be SAFE_TO_AUTOMATE
3. **SQL extraction** — Parses SQL from AI response (```sql blocks)
4. **Destructive keyword blocking** — Rejects DROP, TRUNCATE, ALTER, GRANT, REVOKE, CREATE, DELETE FROM
5. **DML-only enforcement** — Only UPDATE, INSERT, MERGE allowed
6. **Idempotency check** — Prevents duplicate execution via REMEDIATION_AUDIT
7. **Audit logging** — Full record in REMEDIATION_AUDIT

## Key Tables

| Table | Purpose |
|---|---|
| `AI_RECOMMENDATIONS` | AI-generated remediation recommendations |
| `APPROVAL_QUEUE` | Items pending human review |
| `REMEDIATION_AUDIT` | Complete audit trail |
| `V_PENDING_REMEDIATIONS` | View: current items awaiting action |
| `V_REMEDIATION_HISTORY` | View: historical actions with outcomes |

## Principles

- Remediation is never auto-executed from the Streamlit UI
- Only SAFE_TO_AUTOMATE fixes can be auto-applied
- All fixes are audited
- Revalidation via SP_AI_RERUN_AND_SCORE confirms fix effectiveness
