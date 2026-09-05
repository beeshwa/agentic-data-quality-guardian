# DQ Check Catalog

All 25 checks in `CONFIG.DQ_CHECK_LIBRARY`. The engine executes these via SQL template substitution.

| # | Check Name | Category | Severity | Weight | AI |
|---|---|---|---|---|---|
| 1 | Null or Missing Values | Completeness | HIGH | 1.50 | |
| 2 | Primary Key Uniqueness | Integrity | CRITICAL | 2.00 | |
| 3 | Duplicate Record Detection | Integrity | HIGH | 1.50 | |
| 4 | Referential Integrity | Integrity | CRITICAL | 2.00 | |
| 5 | Data Type Validation | Schema | HIGH | 1.25 | |
| 6 | Numeric Range Validation | Validity | MEDIUM | 1.00 | |
| 7 | String Length Validation | Validity | LOW | 0.75 | |
| 8 | Regex Pattern Validation | Validity | MEDIUM | 1.00 | |
| 9 | Allowed Values / Domain Validation | Validity | MEDIUM | 1.00 | |
| 10 | Business Rule Consistency | Consistency | HIGH | 1.50 | Yes |
| 11 | Cross-Column Consistency | Consistency | MEDIUM | 1.25 | Yes |
| 12 | Timeliness / Freshness | Timeliness | CRITICAL | 2.00 | |
| 13 | Completeness | Completeness | HIGH | 1.50 | |
| 14 | Volume Check | Volumetric | HIGH | 1.25 | |
| 15 | Distribution Check | Statistical | MEDIUM | 1.00 | Yes |
| 16 | Outlier Detection | Statistical | MEDIUM | 1.00 | Yes |
| 17 | Schema Drift Detection | Schema | CRITICAL | 2.00 | |
| 18 | End-to-End Reconciliation | Reconciliation | CRITICAL | 2.00 | |
| 19 | Duplicate File Ingestion | Ingestion | HIGH | 1.50 | |
| 20 | Negative Value Check | Validity | MEDIUM | 1.00 | |
| 21 | Percentage / Total Consistency | Consistency | HIGH | 1.50 | |
| 22 | Hierarchy Validation | Integrity | HIGH | 1.50 | |
| 23 | Multi-Source Consistency | Reconciliation | HIGH | 1.50 | Yes |
| 24 | Audit Column Validation | Governance | MEDIUM | 1.00 | |
| 25 | CDC Consistency | Governance | HIGH | 1.50 | |

## Severity Distribution

- **CRITICAL** (5): Checks 2, 4, 12, 17, 18
- **HIGH** (11): Checks 1, 3, 5, 10, 13, 14, 19, 21, 22, 23, 25
- **MEDIUM** (8): Checks 6, 8, 9, 11, 15, 16, 20, 24
- **LOW** (1): Check 7

## AI-Enhanced Checks (5)

| # | Check | AI Use Case |
|---|---|---|
| 10 | Business Rule Consistency | Complex rule interpretation |
| 11 | Cross-Column Consistency | Relationship detection |
| 15 | Distribution Check | Anomaly analysis |
| 16 | Outlier Detection | Contextual assessment |
| 23 | Multi-Source Consistency | Cross-source reasoning |
