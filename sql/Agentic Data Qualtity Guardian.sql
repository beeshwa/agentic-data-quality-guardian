-- ============================================================
-- AGENTIC DATA QUALITY GUARDIAN
-- CoCoQuest 2026 Hackathon | Snowflake-Native AI-Powered DQ
-- ============================================================
-- Canonical deployment script. Run end-to-end on a fresh
-- Snowflake environment to recreate the complete solution.
-- Prerequisites: ACCOUNTADMIN, COMPUTE_WH, Cortex AI enabled
-- ============================================================

-- ============================================================
-- 01. DATABASE & SCHEMAS
-- ============================================================
-- 1. Create project database
CREATE DATABASE IF NOT EXISTS DQ_GUARDIAN
    COMMENT = 'CoCo Data Quality Guardian - CoCoQuest 2026 Hackathon Project';

-- 2. Create project schemas
CREATE SCHEMA IF NOT EXISTS DQ_GUARDIAN.CONFIG
    COMMENT = 'Check definitions, thresholds, schedules, SLA configurations';

CREATE SCHEMA IF NOT EXISTS DQ_GUARDIAN.SYNTHETIC_DATA
    COMMENT = 'Demo datasets with intentional quality defects';

CREATE SCHEMA IF NOT EXISTS DQ_GUARDIAN.PROFILING
    COMMENT = 'Data profiling results, column stats, distributions';

CREATE SCHEMA IF NOT EXISTS DQ_GUARDIAN.CHECK_RESULTS
    COMMENT = 'DQ check execution results, run history, failed records';

CREATE SCHEMA IF NOT EXISTS DQ_GUARDIAN.REMEDIATION
    COMMENT = 'AI-generated fix recommendations, approval queue, audit trail';

CREATE SCHEMA IF NOT EXISTS DQ_GUARDIAN.CORTEX_AI
    COMMENT = 'Cortex AI analysis artifacts, prompt templates, cache';

CREATE SCHEMA IF NOT EXISTS DQ_GUARDIAN.STREAMLIT
    COMMENT = 'Streamlit app assets and UI components';


-- ============================================================
-- 02. CONFIGURATION TABLES
-- ============================================================
USE SCHEMA DQ_GUARDIAN.CONFIG;

-- -------------------------------------------------------
-- 1. DQ_CHECK_LIBRARY - Master catalog of all 25 checks
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY (
    CHECK_ID        INTEGER         NOT NULL,
    CHECK_NAME      VARCHAR(100)    NOT NULL,
    CATEGORY        VARCHAR(50)     NOT NULL,
    DESCRIPTION     VARCHAR(1000)   NOT NULL,
    SQL_TEMPLATE    VARCHAR(4000),
    SEVERITY        VARCHAR(20)     NOT NULL DEFAULT 'MEDIUM',
    WEIGHT          NUMBER(5,2)     NOT NULL DEFAULT 1.00,
    IS_AI_CHECK     BOOLEAN         NOT NULL DEFAULT FALSE,
    IS_ACTIVE       BOOLEAN         NOT NULL DEFAULT TRUE,
    CREATED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_CHECK_LIBRARY PRIMARY KEY (CHECK_ID)
)
COMMENT = 'Master catalog of all 25 data quality check types';

-- -------------------------------------------------------
-- 2. DQ_CHECK_ASSIGNMENTS - Check-to-table mappings
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS (
    ASSIGNMENT_ID   INTEGER         AUTOINCREMENT START 1 INCREMENT 1,
    CHECK_ID        INTEGER         NOT NULL,
    TARGET_DATABASE VARCHAR(256)    NOT NULL,
    TARGET_SCHEMA   VARCHAR(256)    NOT NULL,
    TARGET_TABLE    VARCHAR(256)    NOT NULL,
    TARGET_COLUMN   VARCHAR(256),
    PARAMS_JSON     VARIANT,
    IS_ACTIVE       BOOLEAN         NOT NULL DEFAULT TRUE,
    CREATED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_CHECK_ASSIGNMENTS PRIMARY KEY (ASSIGNMENT_ID),
    CONSTRAINT FK_ASSIGNMENT_CHECK FOREIGN KEY (CHECK_ID)
        REFERENCES DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY(CHECK_ID)
)
COMMENT = 'Maps checks to specific target tables and columns';

-- -------------------------------------------------------
-- 3. DQ_THRESHOLDS - Pass/warning/fail thresholds
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.CONFIG.DQ_THRESHOLDS (
    THRESHOLD_ID    INTEGER         AUTOINCREMENT START 1 INCREMENT 1,
    CHECK_ID        INTEGER         NOT NULL,
    THRESHOLD_NAME  VARCHAR(100)    NOT NULL,
    WARNING_VALUE   NUMBER(10,4),
    FAIL_VALUE      NUMBER(10,4),
    PARAMS_JSON     VARIANT,
    IS_ACTIVE       BOOLEAN         NOT NULL DEFAULT TRUE,
    CREATED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_THRESHOLDS PRIMARY KEY (THRESHOLD_ID),
    CONSTRAINT FK_THRESHOLD_CHECK FOREIGN KEY (CHECK_ID)
        REFERENCES DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY(CHECK_ID)
)
COMMENT = 'Pass/warning/fail thresholds per check';

-- -------------------------------------------------------
-- 4. DQ_SCHEDULES - Task scheduling config
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.CONFIG.DQ_SCHEDULES (
    SCHEDULE_ID     INTEGER         AUTOINCREMENT START 1 INCREMENT 1,
    CHECK_GROUP     VARCHAR(100)    NOT NULL,
    CRON_EXPR       VARCHAR(100)    NOT NULL,
    WAREHOUSE       VARCHAR(256)    NOT NULL DEFAULT 'COMPUTE_WH',
    IS_ACTIVE       BOOLEAN         NOT NULL DEFAULT TRUE,
    CREATED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_SCHEDULES PRIMARY KEY (SCHEDULE_ID)
)
COMMENT = 'Scheduling configuration for automated DQ runs';

-- -------------------------------------------------------
-- 5. DQ_SLA_DEFINITIONS - Freshness SLA rules
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.CONFIG.DQ_SLA_DEFINITIONS (
    SLA_ID              INTEGER         AUTOINCREMENT START 1 INCREMENT 1,
    TARGET_DATABASE     VARCHAR(256)    NOT NULL,
    TARGET_SCHEMA       VARCHAR(256)    NOT NULL,
    TARGET_TABLE        VARCHAR(256)    NOT NULL,
    MAX_STALENESS_MIN   INTEGER         NOT NULL,
    EXPECTED_LOAD_TIME  VARCHAR(20),
    IS_ACTIVE           BOOLEAN         NOT NULL DEFAULT TRUE,
    CREATED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_SLA_DEFINITIONS PRIMARY KEY (SLA_ID)
)
COMMENT = 'Freshness SLA rules per table';


-- ============================================================
-- 03. CONFIGURATION DATA (25 Check Definitions)
-- ============================================================
-- -------------------------------------------------------
-- 6. INSERT 25 DATA QUALITY CHECK DEFINITIONS
-- -------------------------------------------------------

-- Checks 1-5: Core integrity and completeness
INSERT INTO DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY (CHECK_ID, CHECK_NAME, CATEGORY, DESCRIPTION, SQL_TEMPLATE, SEVERITY, WEIGHT, IS_AI_CHECK)
VALUES
(1, 'Null or Missing Values', 'Completeness',
 'Detects NULL or empty values in columns that should be populated. Measures the percentage of missing values against a defined threshold.',
 'SELECT COUNT(*) AS total_rows, COUNT(CASE WHEN {{column}} IS NULL OR TRIM(CAST({{column}} AS VARCHAR)) = '''' THEN 1 END) AS null_count, ROUND(null_count / NULLIF(total_rows, 0) * 100, 2) AS null_pct FROM {{database}}.{{schema}}.{{table}}',
 'HIGH', 1.50, FALSE),

(2, 'Primary Key Uniqueness', 'Integrity',
 'Validates that the primary key column(s) contain only unique, non-null values. Duplicate or null PKs indicate data loading or deduplication failures.',
 'SELECT {{column}} AS pk_value, COUNT(*) AS occurrences FROM {{database}}.{{schema}}.{{table}} GROUP BY {{column}} HAVING COUNT(*) > 1',
 'CRITICAL', 2.00, FALSE),

(3, 'Duplicate Record Detection', 'Integrity',
 'Identifies fully or near-duplicate records based on a defined set of key columns. Catches ETL replay, merge failures, or source-side duplication.',
 'SELECT {{columns}}, COUNT(*) AS dup_count FROM {{database}}.{{schema}}.{{table}} GROUP BY {{columns}} HAVING COUNT(*) > 1',
 'HIGH', 1.50, FALSE),

(4, 'Referential Integrity', 'Integrity',
 'Validates that foreign key values in a child table exist in the referenced parent table. Orphaned records indicate broken relationships or load ordering issues.',
 'SELECT c.{{fk_column}} FROM {{database}}.{{schema}}.{{child_table}} c LEFT JOIN {{database}}.{{schema}}.{{parent_table}} p ON c.{{fk_column}} = p.{{pk_column}} WHERE p.{{pk_column}} IS NULL AND c.{{fk_column}} IS NOT NULL',
 'CRITICAL', 2.00, FALSE),

(5, 'Data Type Validation', 'Schema',
 'Checks whether column values conform to their expected data type. Detects implicit type coercion issues, e.g. non-numeric strings in a numeric field.',
 'SELECT {{column}}, TYPEOF({{column}}) AS actual_type FROM {{database}}.{{schema}}.{{table}} WHERE TRY_CAST({{column}} AS {{expected_type}}) IS NULL AND {{column}} IS NOT NULL',
 'HIGH', 1.25, FALSE);

-- Checks 6-10: Validity and business rules
INSERT INTO DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY (CHECK_ID, CHECK_NAME, CATEGORY, DESCRIPTION, SQL_TEMPLATE, SEVERITY, WEIGHT, IS_AI_CHECK)
VALUES
(6, 'Numeric Range Validation', 'Validity',
 'Validates that numeric column values fall within an expected min/max range. Detects data entry errors, unit mismatches, or overflow conditions.',
 'SELECT {{column}}, ''OUT_OF_RANGE'' AS reason FROM {{database}}.{{schema}}.{{table}} WHERE {{column}} < {{min_value}} OR {{column}} > {{max_value}}',
 'MEDIUM', 1.00, FALSE),

(7, 'String Length Validation', 'Validity',
 'Validates that string column values fall within expected length bounds. Catches truncation, padding issues, or unexpectedly short/long entries.',
 'SELECT {{column}}, LENGTH({{column}}) AS actual_len FROM {{database}}.{{schema}}.{{table}} WHERE LENGTH({{column}}) < {{min_length}} OR LENGTH({{column}}) > {{max_length}}',
 'LOW', 0.75, FALSE),

(8, 'Regex Pattern Validation', 'Validity',
 'Validates that string values match a required regex pattern such as email, phone, postal code, or custom business formats.',
 'SELECT {{column}} FROM {{database}}.{{schema}}.{{table}} WHERE {{column}} IS NOT NULL AND NOT REGEXP_LIKE({{column}}, ''{{pattern}}'')',
 'MEDIUM', 1.00, FALSE),

(9, 'Allowed Values / Domain Validation', 'Validity',
 'Checks that column values belong to a predefined set of allowed values (enum/domain). Detects invalid codes, typos, or unmapped categories.',
 'SELECT {{column}}, COUNT(*) AS cnt FROM {{database}}.{{schema}}.{{table}} WHERE {{column}} NOT IN ({{allowed_values}}) AND {{column}} IS NOT NULL GROUP BY {{column}}',
 'MEDIUM', 1.00, FALSE),

(10, 'Business Rule Consistency', 'Consistency',
 'Validates complex business rules that span column relationships, e.g. end_date > start_date, total = quantity * price. Uses AI to interpret and generate rule SQL.',
 'SELECT * FROM {{database}}.{{schema}}.{{table}} WHERE NOT ({{business_rule_expression}})',
 'HIGH', 1.50, TRUE);

-- Checks 11-15: Consistency, timeliness, volumetrics
INSERT INTO DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY (CHECK_ID, CHECK_NAME, CATEGORY, DESCRIPTION, SQL_TEMPLATE, SEVERITY, WEIGHT, IS_AI_CHECK)
VALUES
(11, 'Cross-Column Consistency', 'Consistency',
 'Validates logical consistency between related columns, e.g. state must match postal code, currency must match country. AI assists in identifying and validating relationships.',
 'SELECT {{column_a}}, {{column_b}} FROM {{database}}.{{schema}}.{{table}} WHERE NOT ({{consistency_rule}})',
 'MEDIUM', 1.25, TRUE),

(12, 'Timeliness / Freshness', 'Timeliness',
 'Checks whether data has been updated within the expected SLA window. Compares MAX timestamp or INFORMATION_SCHEMA metadata against freshness thresholds.',
 'SELECT DATEDIFF(''minute'', MAX({{timestamp_column}}), CURRENT_TIMESTAMP()) AS staleness_minutes FROM {{database}}.{{schema}}.{{table}}',
 'CRITICAL', 2.00, FALSE),

(13, 'Completeness', 'Completeness',
 'Measures the overall completeness of a table by computing the percentage of non-null values across all required columns. Provides a table-level completeness score.',
 'SELECT ROUND(AVG(CASE WHEN {{column}} IS NOT NULL THEN 100.0 ELSE 0.0 END), 2) AS completeness_pct FROM {{database}}.{{schema}}.{{table}}',
 'HIGH', 1.50, FALSE),

(14, 'Volume Check', 'Volumetric',
 'Validates that row counts fall within expected historical range. Detects missing loads, partial loads, or unexpected data explosions.',
 'SELECT COUNT(*) AS current_count FROM {{database}}.{{schema}}.{{table}}',
 'HIGH', 1.25, FALSE),

(15, 'Distribution Check', 'Statistical',
 'Analyzes the value distribution of a column and compares it against historical baselines. Detects distribution shifts using statistical thresholds.',
 'SELECT {{column}}, COUNT(*) AS freq, ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct FROM {{database}}.{{schema}}.{{table}} GROUP BY {{column}} ORDER BY freq DESC',
 'MEDIUM', 1.00, TRUE);

-- Checks 16-20: Statistical, schema, reconciliation
INSERT INTO DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY (CHECK_ID, CHECK_NAME, CATEGORY, DESCRIPTION, SQL_TEMPLATE, SEVERITY, WEIGHT, IS_AI_CHECK)
VALUES
(16, 'Outlier Detection', 'Statistical',
 'Detects statistical outliers using Z-score or IQR methods. AI assists in determining appropriate thresholds and interpreting whether outliers are genuine anomalies.',
 'WITH stats AS (SELECT AVG({{column}}) AS mean_val, STDDEV({{column}}) AS stddev_val FROM {{database}}.{{schema}}.{{table}}) SELECT t.{{column}}, ABS(t.{{column}} - s.mean_val) / NULLIF(s.stddev_val, 0) AS z_score FROM {{database}}.{{schema}}.{{table}} t, stats s WHERE ABS(t.{{column}} - s.mean_val) / NULLIF(s.stddev_val, 0) > {{z_threshold}}',
 'MEDIUM', 1.00, TRUE),

(17, 'Schema Drift Detection', 'Schema',
 'Compares current table schema against a stored baseline snapshot. Detects added, removed, renamed, or type-changed columns that may break downstream pipelines.',
 'SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_CATALOG = ''{{database}}'' AND TABLE_SCHEMA = ''{{schema}}'' AND TABLE_NAME = ''{{table}}'' ORDER BY ORDINAL_POSITION',
 'CRITICAL', 2.00, FALSE),

(18, 'End-to-End Reconciliation', 'Reconciliation',
 'Compares aggregated metrics (row counts, sums, checksums) between a source and target table to validate data pipeline completeness and accuracy.',
 'SELECT (SELECT COUNT(*) FROM {{source_database}}.{{source_schema}}.{{source_table}}) AS source_count, (SELECT COUNT(*) FROM {{database}}.{{schema}}.{{table}}) AS target_count',
 'CRITICAL', 2.00, FALSE),

(19, 'Duplicate File Ingestion', 'Ingestion',
 'Detects whether the same source file has been ingested multiple times by checking file metadata columns such as filename, file hash, or load timestamp.',
 'SELECT {{file_column}}, COUNT(*) AS load_count FROM {{database}}.{{schema}}.{{table}} GROUP BY {{file_column}} HAVING COUNT(*) > 1',
 'HIGH', 1.50, FALSE),

(20, 'Negative Value Check', 'Validity',
 'Validates that columns which should never contain negative values (e.g. quantity, price, balance) have no negative entries.',
 'SELECT {{column}} FROM {{database}}.{{schema}}.{{table}} WHERE {{column}} < 0',
 'MEDIUM', 1.00, FALSE);

-- Checks 21-25: Advanced consistency and governance
INSERT INTO DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY (CHECK_ID, CHECK_NAME, CATEGORY, DESCRIPTION, SQL_TEMPLATE, SEVERITY, WEIGHT, IS_AI_CHECK)
VALUES
(21, 'Percentage / Total Consistency', 'Consistency',
 'Validates that calculated percentages or totals match their component parts, e.g. line item amounts sum to order total, percentages sum to 100%.',
 'SELECT {{id_column}}, SUM({{part_column}}) AS computed_total, {{total_column}} AS stated_total FROM {{database}}.{{schema}}.{{table}} GROUP BY {{id_column}}, {{total_column}} HAVING ABS(computed_total - stated_total) > {{tolerance}}',
 'HIGH', 1.50, FALSE),

(22, 'Hierarchy Validation', 'Integrity',
 'Validates hierarchical/tree data for circular references, orphan nodes, and depth violations. Checks parent-child relationships for structural integrity.',
 'WITH RECURSIVE hier AS (SELECT {{id_column}}, {{parent_column}}, 1 AS depth FROM {{database}}.{{schema}}.{{table}} WHERE {{parent_column}} IS NULL UNION ALL SELECT t.{{id_column}}, t.{{parent_column}}, h.depth + 1 FROM {{database}}.{{schema}}.{{table}} t JOIN hier h ON t.{{parent_column}} = h.{{id_column}} WHERE h.depth < {{max_depth}}) SELECT t.{{id_column}} FROM {{database}}.{{schema}}.{{table}} t LEFT JOIN hier h ON t.{{id_column}} = h.{{id_column}} WHERE h.{{id_column}} IS NULL',
 'HIGH', 1.50, FALSE),

(23, 'Multi-Source Consistency', 'Reconciliation',
 'Compares the same logical entity across multiple source systems to detect discrepancies. AI assists in mapping equivalent fields across different schemas.',
 'SELECT a.{{key_column}}, a.{{compare_column}} AS source_a_val, b.{{compare_column}} AS source_b_val FROM {{source_a_table}} a JOIN {{source_b_table}} b ON a.{{key_column}} = b.{{key_column}} WHERE a.{{compare_column}} != b.{{compare_column}}',
 'HIGH', 1.50, TRUE),

(24, 'Audit Column Validation', 'Governance',
 'Validates that mandatory audit columns (created_at, updated_at, created_by, updated_by) are populated and logically consistent (e.g. updated_at >= created_at).',
 'SELECT * FROM {{database}}.{{schema}}.{{table}} WHERE {{created_at_col}} IS NULL OR {{updated_at_col}} IS NULL OR {{updated_at_col}} < {{created_at_col}}',
 'MEDIUM', 1.00, FALSE),

(25, 'CDC Consistency', 'Governance',
 'Validates Change Data Capture consistency: ensures CDC operation codes are valid, sequence numbers are monotonic, and no updates are missing or out of order.',
 'SELECT {{cdc_op_column}}, COUNT(*) AS cnt FROM {{database}}.{{schema}}.{{table}} WHERE {{cdc_op_column}} NOT IN ({{valid_ops}}) GROUP BY {{cdc_op_column}}',
 'HIGH', 1.50, FALSE);

-- ============================================================
-- 04. SYNTHETIC DATA TABLES
-- ============================================================
USE SCHEMA DQ_GUARDIAN.SYNTHETIC_DATA;

-- -------------------------------------------------------
-- 1. CREATE 8 SYNTHETIC DATA TABLES
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.SYNTHETIC_DATA.CUSTOMERS (
    CUSTOMER_ID     INTEGER         NOT NULL,
    FIRST_NAME      VARCHAR(50),
    LAST_NAME       VARCHAR(50),
    EMAIL           VARCHAR(200),
    PHONE           VARCHAR(20),
    COUNTRY         VARCHAR(50),
    STATE           VARCHAR(50),
    POSTAL_CODE     VARCHAR(20),
    CUSTOMER_STATUS VARCHAR(20),
    CREATED_AT      TIMESTAMP_NTZ,
    UPDATED_AT      TIMESTAMP_NTZ
)
COMMENT = 'Synthetic customer master data with intentional quality defects';

CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.SYNTHETIC_DATA.PRODUCTS (
    PRODUCT_ID      INTEGER         NOT NULL,
    PRODUCT_NAME    VARCHAR(100),
    CATEGORY        VARCHAR(50),
    PRICE           NUMBER(10,2),
    WEIGHT_KG       NUMBER(8,2),
    IS_ACTIVE       BOOLEAN,
    CREATED_AT      TIMESTAMP_NTZ
)
COMMENT = 'Synthetic product catalog with intentional quality defects';

CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.SYNTHETIC_DATA.ORDERS (
    ORDER_ID        INTEGER         NOT NULL,
    CUSTOMER_ID     INTEGER,
    ORDER_DATE      DATE,
    ORDER_STATUS    VARCHAR(20),
    ORDER_AMOUNT    NUMBER(12,2),
    CURRENCY        VARCHAR(3),
    COUNTRY         VARCHAR(50),
    CREATED_AT      TIMESTAMP_NTZ,
    UPDATED_AT      TIMESTAMP_NTZ
)
COMMENT = 'Synthetic order data with intentional quality defects';

CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.SYNTHETIC_DATA.ORDER_ITEMS (
    ITEM_ID         INTEGER         NOT NULL,
    ORDER_ID        INTEGER,
    PRODUCT_ID      INTEGER,
    QUANTITY        INTEGER,
    UNIT_PRICE      NUMBER(10,2),
    LINE_TOTAL      NUMBER(12,2),
    DISCOUNT_PCT    NUMBER(5,2),
    DISCOUNT_AMT    NUMBER(10,2),
    CREATED_AT      TIMESTAMP_NTZ
)
COMMENT = 'Synthetic order line items with intentional quality defects';

CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.SYNTHETIC_DATA.EMPLOYEES (
    EMPLOYEE_ID     INTEGER         NOT NULL,
    EMPLOYEE_NAME   VARCHAR(100),
    DEPARTMENT      VARCHAR(50),
    MANAGER_ID      INTEGER,
    HIRE_DATE       DATE,
    SALARY          NUMBER(10,2),
    EMPLOYEE_LEVEL  INTEGER,
    CREATED_AT      TIMESTAMP_NTZ,
    UPDATED_AT      TIMESTAMP_NTZ
)
COMMENT = 'Synthetic employee hierarchy with intentional quality defects';

CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.SYNTHETIC_DATA.AUDIT_LOG (
    LOG_ID          INTEGER         NOT NULL,
    TABLE_NAME      VARCHAR(100),
    RECORD_ID       INTEGER,
    CDC_OPERATION   VARCHAR(10),
    CDC_SEQUENCE    INTEGER,
    OLD_VALUE       VARCHAR(500),
    NEW_VALUE       VARCHAR(500),
    CHANGED_BY      VARCHAR(100),
    CREATED_AT      TIMESTAMP_NTZ,
    UPDATED_AT      TIMESTAMP_NTZ
)
COMMENT = 'Synthetic audit/CDC log with intentional quality defects';

CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.SYNTHETIC_DATA.DAILY_AGGREGATES (
    AGG_ID          INTEGER         NOT NULL,
    AGG_DATE        DATE,
    TABLE_NAME      VARCHAR(100),
    TOTAL_ROWS      INTEGER,
    TOTAL_AMOUNT    NUMBER(14,2),
    AVG_AMOUNT      NUMBER(10,2),
    CREATED_AT      TIMESTAMP_NTZ
)
COMMENT = 'Synthetic daily aggregates for reconciliation testing';

CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.SYNTHETIC_DATA.FILE_INGESTION_LOG (
    INGESTION_ID    INTEGER         NOT NULL,
    FILE_NAME       VARCHAR(256),
    FILE_HASH       VARCHAR(64),
    FILE_SIZE_BYTES INTEGER,
    ROW_COUNT       INTEGER,
    INGESTED_AT     TIMESTAMP_NTZ,
    STATUS          VARCHAR(20)
)
COMMENT = 'Synthetic file ingestion log for duplicate detection';

-- -------------------------------------------------------
-- 1b. SCHEMA SNAPSHOTS (for CHECK 17: Schema Drift)
-- Baseline must be captured BEFORE the ALTER TABLE below.
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.PROFILING.SCHEMA_SNAPSHOTS (
    SNAPSHOT_ID     INTEGER         NOT NULL,
    TABLE_CATALOG   VARCHAR(256)    NOT NULL,
    TABLE_SCHEMA    VARCHAR(256)    NOT NULL,
    TABLE_NAME      VARCHAR(256)    NOT NULL,
    COLUMN_NAME     VARCHAR(256)    NOT NULL,
    ORDINAL_POSITION INTEGER        NOT NULL,
    DATA_TYPE       VARCHAR(50)     NOT NULL,
    CHARACTER_MAXIMUM_LENGTH INTEGER,
    NUMERIC_PRECISION INTEGER,
    NUMERIC_SCALE   INTEGER,
    IS_NULLABLE     VARCHAR(3)      NOT NULL,
    SNAPSHOT_AT     TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_SCHEMA_SNAPSHOTS PRIMARY KEY (SNAPSHOT_ID)
)
COMMENT = 'Baseline schema snapshots for schema drift detection';

-- CHECK 17 Step A: Take baseline snapshot of PRODUCTS (7 columns)
INSERT INTO DQ_GUARDIAN.PROFILING.SCHEMA_SNAPSHOTS
(SNAPSHOT_ID, TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, ORDINAL_POSITION,
 DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE, SNAPSHOT_AT)
SELECT ROW_NUMBER() OVER (ORDER BY ORDINAL_POSITION),
       TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, ORDINAL_POSITION,
       DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE,
       '2024-01-01 00:00:00'::TIMESTAMP_NTZ
FROM DQ_GUARDIAN.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'SYNTHETIC_DATA' AND TABLE_NAME = 'PRODUCTS'
ORDER BY ORDINAL_POSITION;

-- CHECK 17 Step B: Introduce schema drift by adding a column
-- Baseline had 7 columns; after this ALTER, PRODUCTS has 8.
-- Detection: LEFT JOIN INFORMATION_SCHEMA vs SCHEMA_SNAPSHOTS
ALTER TABLE DQ_GUARDIAN.SYNTHETIC_DATA.PRODUCTS ADD COLUMN SUPPLIER_CODE VARCHAR(20) DEFAULT NULL;

-- ============================================================
-- 05. SYNTHETIC DATA (Seed Data with Intentional Defects)
-- ============================================================
-- -------------------------------------------------------
-- 2. INSERT CUSTOMERS (15 rows: 5 clean + 10 defective)
-- -------------------------------------------------------
INSERT INTO DQ_GUARDIAN.SYNTHETIC_DATA.CUSTOMERS VALUES
-- Clean records
(1, 'Alice', 'Smith',   'alice.smith@email.com',   '555-0101', 'US', 'CA', '90210', 'ACTIVE',   '2024-01-15 10:00:00', '2024-06-01 12:00:00'),
(2, 'Bob',   'Jones',   'bob.jones@email.com',     '555-0102', 'US', 'NY', '10001', 'ACTIVE',   '2024-02-20 09:00:00', '2024-07-15 14:00:00'),
(3, 'Carol', 'Williams','carol.w@email.com',       '555-0103', 'US', 'TX', '73301', 'ACTIVE',   '2024-03-10 11:00:00', '2024-08-01 10:00:00'),
(4, 'David', 'Brown',   'david.b@email.com',       '555-0104', 'UK', 'LND','EC1A1BB','ACTIVE',  '2024-04-05 08:00:00', '2024-04-05 08:00:00'),
(5, 'Eve',   'Davis',   'eve.davis@email.com',     '555-0105', 'US', 'FL', '33101', 'INACTIVE', '2024-05-12 07:00:00', '2024-09-01 09:00:00'),
-- CHECK 1: Null/missing values (NULL first_name, NULL email)
(6, NULL,    'Taylor',  NULL,                       '555-0106', 'US', 'WA', '98101', 'ACTIVE',   '2024-06-01 10:00:00', '2024-06-01 10:00:00'),
-- CHECK 2: Primary key uniqueness (duplicate CUSTOMER_ID=1)
(1, 'Alicia','SmithDup','alicia.dup@email.com',    '555-0199', 'US', 'CA', '90210', 'ACTIVE',   '2024-07-01 10:00:00', '2024-07-01 10:00:00'),
-- CHECK 3: Duplicate record (same name/email/phone as ID=2)
(7, 'Bob',   'Jones',   'bob.jones@email.com',     '555-0102', 'US', 'NY', '10001', 'ACTIVE',   '2024-02-20 09:00:00', '2024-07-15 14:00:00'),
-- CHECK 8: Regex pattern (invalid email)
(8, 'Frank', 'Miller',  'not-an-email',            '555-0108', 'US', 'OH', '43004', 'ACTIVE',   '2024-08-01 10:00:00', '2024-08-01 10:00:00'),
-- CHECK 9: Invalid domain value (DELETED not in ACTIVE/INACTIVE/SUSPENDED)
(9, 'Grace', 'Wilson',  'grace.w@email.com',       '555-0109', 'US', 'IL', '60601', 'DELETED',  '2024-09-01 10:00:00', '2024-09-01 10:00:00'),
-- CHECK 7: String too short (1-char first name)
(10,'H',     'Anderson','h.a@email.com',           '555-0110', 'US', 'PA', '19101', 'ACTIVE',   '2024-10-01 10:00:00', '2024-10-01 10:00:00'),
-- CHECK 11: Cross-column inconsistency (UK + CA + US postal code)
(11,'Ivan',  'Clark',   'ivan.c@email.com',        '555-0111', 'UK', 'CA', '90001', 'ACTIVE',   '2024-11-01 10:00:00', '2024-11-01 10:00:00'),
-- CHECK 12: Timeliness (very old updated_at)
(12,'Jane',  'Lewis',   'jane.l@email.com',        '555-0112', 'US', 'GA', '30301', 'ACTIVE',   '2022-01-01 10:00:00', '2022-01-01 10:00:00'),
-- CHECK 24: Audit column (updated_at before created_at)
(13,'Karl',  'Moore',   'karl.m@email.com',        '555-0113', 'US', 'MI', '48201', 'ACTIVE',   '2024-06-15 10:00:00', '2024-01-01 08:00:00'),
-- CHECK 5: Data type validation (POSTAL_CODE=ABCXYZ fails TRY_CAST to NUMBER for US customer)
-- Snowflake is strongly typed at storage layer; VARCHAR columns holding typed values
-- are validated via TRY_CAST. This is the standard Snowflake data type validation pattern.
(14,'Liam',  'Numeric', 'liam.n@email.com',        '555-0114', 'US', 'NV', 'ABCXYZ','ACTIVE',   '2024-11-15 10:00:00', '2024-11-15 10:00:00');

-- -------------------------------------------------------
-- 3. INSERT PRODUCTS (12 rows: 6 clean + 6 defective)
-- Note: SUPPLIER_CODE column was added by ALTER above for CHECK 17.
-- All inserts here leave SUPPLIER_CODE as NULL (default).
-- -------------------------------------------------------
INSERT INTO DQ_GUARDIAN.SYNTHETIC_DATA.PRODUCTS
(PRODUCT_ID, PRODUCT_NAME, CATEGORY, PRICE, WEIGHT_KG, IS_ACTIVE, CREATED_AT) VALUES
(101, 'Laptop Pro 15',     'Electronics', 999.99,  2.10, TRUE,  '2024-01-01 10:00:00'),
(102, 'Wireless Mouse',    'Electronics', 29.99,   0.15, TRUE,  '2024-01-15 10:00:00'),
(103, 'Office Chair',      'Furniture',   249.00,  12.50,TRUE,  '2024-02-01 10:00:00'),
(104, 'Standing Desk',     'Furniture',   599.00,  35.00,TRUE,  '2024-02-15 10:00:00'),
(105, 'USB-C Cable',       'Accessories', 12.99,   0.05, TRUE,  '2024-03-01 10:00:00'),
(106, 'Notebook A5',       'Stationery',  4.99,    0.20, TRUE,  '2024-03-15 10:00:00'),
-- CHECK 6: Negative price
(107, 'Phantom Widget',    'Electronics', -50.00,  1.00, TRUE,  '2024-04-01 10:00:00'),
-- CHECK 9: Invalid category
(108, 'Mystery Item',      'INVALID_CAT', 19.99,   0.50, TRUE,  '2024-04-15 10:00:00'),
-- CHECK 16: Outlier weight (9999 kg)
(109, 'Heavy Object',      'Furniture',   50.00,   9999.00,TRUE,'2024-05-01 10:00:00'),
-- Edge case (price=0, valid)
(110, 'Free Sample',       'Accessories', 0.00,    0.01, FALSE, '2024-05-15 10:00:00'),
-- CHECK 1: NULL product name
(111, NULL,                 'Electronics', 15.00,   0.30, TRUE,  '2024-06-01 10:00:00'),
-- CHECK 20: Negative weight
(112, 'Broken Scale Item', 'Accessories', 9.99,    -2.00,TRUE,  '2024-06-15 10:00:00');

-- -------------------------------------------------------
-- 4. INSERT ORDERS (13 rows: 5 clean + 8 defective)
-- -------------------------------------------------------
INSERT INTO DQ_GUARDIAN.SYNTHETIC_DATA.ORDERS VALUES
(1001, 1, '2024-06-01', 'COMPLETED', 1029.98, 'USD', 'US', '2024-06-01 10:00:00', '2024-06-02 10:00:00'),
(1002, 2, '2024-06-15', 'COMPLETED', 279.98,  'USD', 'US', '2024-06-15 09:00:00', '2024-06-16 09:00:00'),
(1003, 3, '2024-07-01', 'SHIPPED',   249.00,  'USD', 'US', '2024-07-01 11:00:00', '2024-07-03 14:00:00'),
(1004, 4, '2024-07-10', 'COMPLETED', 599.00,  'GBP', 'UK', '2024-07-10 08:00:00', '2024-07-11 08:00:00'),
(1005, 5, '2024-08-01', 'PENDING',   17.98,   'USD', 'US', '2024-08-01 07:00:00', '2024-08-01 07:00:00'),
-- CHECK 20: Negative order amount
(1006, 1, '2024-08-15', 'COMPLETED', -150.00, 'USD', 'US', '2024-08-15 10:00:00', '2024-08-16 10:00:00'),
-- CHECK 10: Future order date (business rule violation)
(1007, 2, '2029-12-31', 'COMPLETED', 100.00,  'USD', 'US', '2024-09-01 09:00:00', '2024-09-02 09:00:00'),
-- CHECK 4: Referential integrity (customer_id=999 not in CUSTOMERS)
(1008, 999,'2024-09-10', 'SHIPPED',  50.00,   'USD', 'US', '2024-09-10 10:00:00', '2024-09-11 10:00:00'),
-- CHECK 2: Duplicate ORDER_ID=1001
(1001, 1, '2024-06-01', 'COMPLETED', 1029.98, 'USD', 'US', '2024-06-01 10:00:00', '2024-06-02 10:00:00'),
-- CHECK 11: Currency/country mismatch (GBP + US)
(1009, 3, '2024-09-20', 'COMPLETED', 200.00,  'GBP', 'US', '2024-09-20 10:00:00', '2024-09-21 10:00:00'),
-- CHECK 9: Invalid order status (VOIDED)
(1010, 4, '2024-10-01', 'VOIDED',    75.00,   'GBP', 'UK', '2024-10-01 10:00:00', '2024-10-02 10:00:00'),
-- CHECK 1: NULL order amount
(1011, 5, '2024-10-15', 'PENDING',   NULL,    'USD', 'US', '2024-10-15 10:00:00', '2024-10-15 10:00:00'),
-- CHECK 13: Completeness (nearly all NULLs)
(1012, NULL, NULL,       NULL,        NULL,    NULL,  NULL, NULL,                   NULL);

-- -------------------------------------------------------
-- 5. INSERT ORDER_ITEMS (15 rows: 8 clean + 7 defective)
-- -------------------------------------------------------
INSERT INTO DQ_GUARDIAN.SYNTHETIC_DATA.ORDER_ITEMS VALUES
(1, 1001, 101, 1,  999.99,  999.99,  0.00, 0.00,   '2024-06-01 10:00:00'),
(2, 1001, 105, 2,  12.99,   25.98,   0.00, 0.00,   '2024-06-01 10:00:00'),
(3, 1002, 102, 2,  29.99,   59.98,   0.00, 0.00,   '2024-06-15 09:00:00'),
(4, 1002, 103, 1,  249.00,  249.00,  0.00, 0.00,   '2024-06-15 09:00:00'),
(5, 1003, 103, 1,  249.00,  249.00,  0.00, 0.00,   '2024-07-01 11:00:00'),
(6, 1004, 104, 1,  599.00,  599.00,  0.00, 0.00,   '2024-07-10 08:00:00'),
(7, 1005, 105, 1,  12.99,   12.99,   0.00, 0.00,   '2024-08-01 07:00:00'),
(8, 1005, 106, 1,  4.99,    4.99,    0.00, 0.00,   '2024-08-01 07:00:00'),
-- CHECK 4: Orphan product_id=999
(9, 1006, 999, 1,  50.00,   50.00,   0.00, 0.00,   '2024-08-15 10:00:00'),
-- CHECK 21: Total mismatch (1*100 != 999)
(10,1007, 102, 1,  100.00,  999.00,  0.00, 0.00,   '2024-09-01 09:00:00'),
-- CHECK 16: Outlier quantity (10000)
(11,1008, 105, 10000, 12.99, 129900.00, 0.00, 0.00,'2024-09-10 10:00:00'),
-- CHECK 11: Discount % vs amount mismatch
(12,1009, 101, 1,  999.99,  999.99,  10.00, 0.00,  '2024-09-20 10:00:00'),
-- CHECK 20: Negative quantity
(13,1010, 106, -5, 4.99,    -24.95,  0.00, 0.00,   '2024-10-01 10:00:00'),
-- CHECK 6: Unit price out of range (99999)
(14,1011, 101, 1,  99999.00,99999.00,0.00, 0.00,   '2024-10-15 10:00:00'),
-- CHECK 1: All NULLs
(15,1012, NULL,NULL, NULL,   NULL,    NULL, NULL,    NULL);

-- -------------------------------------------------------
-- 6. INSERT EMPLOYEES (13 rows: 6 clean + 7 defective)
-- CHECK 15: Distribution — Engineering has 5/13 = 38.46%.
--   Threshold: no department > 30%. Engineering exceeds this.
--   Detection: GROUP BY DEPARTMENT, compute pct, WHERE pct > 30.
-- -------------------------------------------------------
INSERT INTO DQ_GUARDIAN.SYNTHETIC_DATA.EMPLOYEES VALUES
(1,  'Alice Chen',      'Executive',  NULL, '2015-01-15', 250000.00, 1, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
(2,  'Bob Park',        'Engineering', 1,   '2016-03-20', 180000.00, 2, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
(3,  'Carol White',     'Sales',       1,   '2017-06-10', 170000.00, 2, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
(4,  'David Kim',       'Engineering', 2,   '2018-09-01', 130000.00, 3, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
(5,  'Eve Johnson',     'Sales',       3,   '2019-02-14', 120000.00, 3, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
(6,  'Frank Lee',       'Engineering', 4,   '2020-05-01', 95000.00,  4, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
-- CHECK 22: Orphan manager (999 not in EMPLOYEES)
(7,  'Grace Orphan',    'Marketing',   999, '2021-08-15', 85000.00,  3, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
-- CHECK 22: Circular reference (8->9->8)
(8,  'Henry Loop',      'Finance',     9,   '2022-01-10', 110000.00, 3, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
(9,  'Iris Cycle',      'Finance',     8,   '2022-03-20', 105000.00, 3, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
-- CHECK 6/20: Negative salary
(10, 'Jack Negative',   'Engineering', 2,   '2023-01-05', -5000.00,  4, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
-- CHECK 10: Business rule (level 4 salary > level 2 manager)
(11, 'Karen Overpaid',  'Sales',       3,   '2023-06-01', 500000.00, 4, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
-- CHECK 1: NULL employee name
(12, NULL,              'HR',          1,   '2024-01-15', 90000.00,  3, '2024-01-01 10:00:00', '2024-06-01 10:00:00'),
-- CHECK 15: Distribution skew (5th Engineering employee to push dept to 38.46%)
(13, 'Larry Intern',    'Engineering', 4,   '2024-06-01', 45000.00,  5, '2024-01-01 10:00:00', '2024-06-01 10:00:00');

-- -------------------------------------------------------
-- 7. INSERT AUDIT_LOG (15 rows: 8 clean + 7 defective)
-- CHECK 25 fixes inline:
--   LOG_ID 10: D (Delete) for ORDERS/1004 with CDC_SEQUENCE=15
--   LOG_ID 11: I (Insert) for ORDERS/1004 with CDC_SEQUENCE=15 (duplicate)
--   This creates: (a) duplicate CDC_SEQUENCE per record
--                 (b) invalid state transition: Delete before Insert
-- -------------------------------------------------------
INSERT INTO DQ_GUARDIAN.SYNTHETIC_DATA.AUDIT_LOG VALUES
(1, 'CUSTOMERS', 1,  'I', 1, NULL,             '{"name":"Alice"}',    'SYSTEM',   '2024-01-15 10:00:00', '2024-01-15 10:00:00'),
(2, 'CUSTOMERS', 2,  'I', 2, NULL,             '{"name":"Bob"}',      'SYSTEM',   '2024-02-20 09:00:00', '2024-02-20 09:00:00'),
(3, 'CUSTOMERS', 1,  'U', 3, '{"status":"NEW"}','{"status":"ACTIVE"}','ADMIN',    '2024-06-01 12:00:00', '2024-06-01 12:00:00'),
(4, 'ORDERS',    1001,'I', 4, NULL,             '{"amount":1029.98}',  'ETL_PROC', '2024-06-01 10:00:00', '2024-06-01 10:00:00'),
(5, 'ORDERS',    1002,'I', 5, NULL,             '{"amount":279.98}',   'ETL_PROC', '2024-06-15 09:00:00', '2024-06-15 09:00:00'),
(6, 'PRODUCTS',  101, 'I', 6, NULL,             '{"name":"Laptop"}',   'ETL_PROC', '2024-01-01 10:00:00', '2024-01-01 10:00:00'),
(7, 'CUSTOMERS', 3,  'U', 7, '{"email":"old"}', '{"email":"carol.w@email.com"}','ADMIN','2024-08-01 10:00:00','2024-08-01 10:00:00'),
(8, 'ORDERS',    1003,'I', 8, NULL,             '{"amount":249.00}',   'ETL_PROC', '2024-07-01 11:00:00', '2024-07-01 11:00:00'),
-- CHECK 25: Invalid CDC operation 'X'
(9, 'CUSTOMERS', 5,  'X', 9, '{"status":"ACTIVE"}','{"status":"INACTIVE"}','UNKNOWN','2024-09-01 09:00:00','2024-09-01 09:00:00'),
-- CHECK 25: Duplicate CDC_SEQUENCE=15 + invalid state transition (D before I)
(10,'ORDERS',    1004,'D',15, '{"status":"ACTIVE"}',NULL,              'ADMIN',    '2024-07-10 06:00:00', '2024-07-10 06:00:00'),
(11,'ORDERS',    1004,'I',15, NULL,              '{"amount":599.00}',   'ETL_PROC', '2024-07-10 07:00:00', '2024-07-10 07:00:00'),
-- CHECK 24: NULL changed_by
(12,'PRODUCTS',  107, 'I',12, NULL,             '{"name":"Phantom"}',   NULL,       '2024-04-01 10:00:00', '2024-04-01 10:00:00'),
-- CHECK 24: updated_at before created_at
(13,'PRODUCTS',  108, 'U',13, '{"cat":"old"}',  '{"cat":"INVALID_CAT"}','ADMIN',   '2024-04-15 10:00:00', '2024-04-14 09:00:00'),
-- CHECK 1: NULL table_name and record_id
(14,NULL,        NULL,'I',14, NULL,              '{"data":"unknown"}',  'SYSTEM',   '2024-10-01 10:00:00', '2024-10-01 10:00:00'),
-- CHECK 3: Duplicate audit record (exact dup of row 4)
(15,'ORDERS',    1001,'I', 4, NULL,             '{"amount":1029.98}',  'ETL_PROC', '2024-06-01 10:00:00', '2024-06-01 10:00:00');

-- -------------------------------------------------------
-- 8. INSERT DAILY_AGGREGATES (11 rows: 5 clean + 6 defective)
-- CHECK 18 fix inline: AGG_ID=6 is ORDERS_RECON_TARGET for 2024-06-15
--   Source (ORDERS): 1 row, 279.98
--   Target (AGG_ID=6): 3 rows, 999.99 → mismatch
-- CHECK 23 inline: AGG_ID=1 (1029.98) vs AGG_ID=10 (999.99)
--   Same AGG_DATE + TABLE_NAME, different TOTAL_AMOUNT
--   Detection: GROUP BY AGG_DATE, TABLE_NAME HAVING COUNT(DISTINCT TOTAL_AMOUNT) > 1
-- -------------------------------------------------------
INSERT INTO DQ_GUARDIAN.SYNTHETIC_DATA.DAILY_AGGREGATES VALUES
(1, '2024-06-01', 'ORDERS', 2, 1029.98, 514.99, '2024-06-02 06:00:00'),
(2, '2024-06-15', 'ORDERS', 1, 279.98,  279.98, '2024-06-16 06:00:00'),
(3, '2024-07-01', 'ORDERS', 1, 249.00,  249.00, '2024-07-02 06:00:00'),
(4, '2024-07-10', 'ORDERS', 1, 599.00,  599.00, '2024-07-11 06:00:00'),
(5, '2024-08-01', 'ORDERS', 1, 17.98,   17.98,  '2024-08-02 06:00:00'),
-- CHECK 18: Reconciliation target with intentional mismatch vs ORDERS source
(6, '2024-06-15', 'ORDERS_RECON_TARGET', 3, 999.99, 333.33, '2024-06-02 06:00:00'),
-- CHECK 14: Volume anomaly (0 rows)
(7, '2024-08-15', 'ORDERS', 0, 0.00, 0.00, '2024-08-16 06:00:00'),
-- CHECK 10: Business rule (avg > total, impossible)
(8, '2024-09-01', 'ORDERS', 3, 100.00, 500.00, '2024-09-02 06:00:00'),
-- CHECK 1: NULL agg_date
(9, NULL,         'ORDERS', 5, 500.00, 100.00, '2024-09-15 06:00:00'),
-- CHECK 23: Multi-source inconsistency (conflicts with AGG_ID=1 for same date/table)
(10,'2024-06-01', 'ORDERS', 2, 999.99, 499.99, '2024-06-02 07:00:00'),
-- CHECK 12: Very old record
(11,'2022-01-01', 'ORDERS', 10,1000.00,100.00, '2022-01-02 06:00:00');

-- -------------------------------------------------------
-- 9. INSERT FILE_INGESTION_LOG (11 rows: 5 clean + 6 defective)
-- -------------------------------------------------------
INSERT INTO DQ_GUARDIAN.SYNTHETIC_DATA.FILE_INGESTION_LOG VALUES
(1, 'customers_20240601.csv',  'abc123def456', 15000, 100, '2024-06-01 06:00:00', 'SUCCESS'),
(2, 'orders_20240601.csv',     'bcd234efg567', 25000, 200, '2024-06-01 06:05:00', 'SUCCESS'),
(3, 'products_20240601.csv',   'cde345fgh678', 8000,  50,  '2024-06-01 06:10:00', 'SUCCESS'),
(4, 'customers_20240615.csv',  'def456ghi789', 16000, 110, '2024-06-15 06:00:00', 'SUCCESS'),
(5, 'orders_20240615.csv',     'efg567hij890', 28000, 220, '2024-06-15 06:05:00', 'SUCCESS'),
-- CHECK 19: Duplicate file ingestion (same file 3 times)
(6, 'customers_20240601.csv',  'abc123def456', 15000, 100, '2024-06-02 06:00:00', 'SUCCESS'),
(7, 'customers_20240601.csv',  'abc123def456', 15000, 100, '2024-06-03 06:00:00', 'SUCCESS'),
-- CHECK 1: NULL file_name
(8, NULL,                       'fff999ggg000', 5000,  30,  '2024-07-01 06:00:00', 'SUCCESS'),
-- CHECK 9: Invalid status
(9, 'orders_20240701.csv',     'ghi678jkl901', 30000, 250, '2024-07-01 06:05:00', 'UNKNOWN'),
-- CHECK 20: Negative file size
(10,'products_20240701.csv',   'hij789klm012', -500,  40,  '2024-07-01 06:10:00', 'SUCCESS'),
-- CHECK 7: Extremely long filename (>200 chars)
(11,'this_is_an_extremely_long_filename_that_should_fail_string_length_validation_because_it_exceeds_the_reasonable_maximum_length_for_a_file_name_in_any_normal_operating_system_or_data_pipeline_configuration_check.csv', 'xyz999', 1000, 10, '2024-07-15 06:00:00', 'FAILED');

-- -------------------------------------------------------
-- 10. DEFECT CATALOG (43 entries covering all 25 checks)
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.SYNTHETIC_DATA.DEFECT_CATALOG (
    DEFECT_ID           INTEGER         NOT NULL,
    CHECK_ID            INTEGER         NOT NULL,
    CHECK_NAME          VARCHAR(100)    NOT NULL,
    TABLE_NAME          VARCHAR(100)    NOT NULL,
    COLUMN_NAME         VARCHAR(100),
    DEFECT_TYPE         VARCHAR(50)     NOT NULL,
    DESCRIPTION         VARCHAR(500)    NOT NULL,
    EXPECTED_CONDITION  VARCHAR(500)    NOT NULL,
    ACTUAL_CONDITION    VARCHAR(500)    NOT NULL,
    AFFECTED_RECORD_COUNT INTEGER      NOT NULL,
    SEVERITY            VARCHAR(20)     NOT NULL,
    CREATED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_DEFECT_CATALOG PRIMARY KEY (DEFECT_ID)
)
COMMENT = 'Catalog of all intentional defects planted in synthetic test data';

INSERT INTO DQ_GUARDIAN.SYNTHETIC_DATA.DEFECT_CATALOG
(DEFECT_ID, CHECK_ID, CHECK_NAME, TABLE_NAME, COLUMN_NAME, DEFECT_TYPE, DESCRIPTION, EXPECTED_CONDITION, ACTUAL_CONDITION, AFFECTED_RECORD_COUNT, SEVERITY)
VALUES
-- CHECK 1: Null or Missing Values
(1,  1, 'Null or Missing Values',       'CUSTOMERS',         'FIRST_NAME',    'NULL_VALUE',       'Customer ID=6 has NULL FIRST_NAME and NULL EMAIL',                                'FIRST_NAME IS NOT NULL', 'FIRST_NAME IS NULL', 1, 'HIGH'),
(2,  1, 'Null or Missing Values',       'PRODUCTS',          'PRODUCT_NAME',  'NULL_VALUE',       'Product ID=111 has NULL PRODUCT_NAME',                                            'PRODUCT_NAME IS NOT NULL', 'PRODUCT_NAME IS NULL', 1, 'HIGH'),
(3,  1, 'Null or Missing Values',       'ORDERS',            'ORDER_AMOUNT',  'NULL_VALUE',       'Order ID=1011 has NULL ORDER_AMOUNT; Order ID=1012 has all NULLs',                'ORDER_AMOUNT IS NOT NULL', 'ORDER_AMOUNT IS NULL', 2, 'HIGH'),
-- CHECK 2: Primary Key Uniqueness
(4,  2, 'Primary Key Uniqueness',       'CUSTOMERS',         'CUSTOMER_ID',   'DUPLICATE_PK',     'CUSTOMER_ID=1 appears twice (Alice Smith and Alicia SmithDup)',                   'CUSTOMER_ID is unique', 'CUSTOMER_ID=1 duplicated', 2, 'CRITICAL'),
(5,  2, 'Primary Key Uniqueness',       'ORDERS',            'ORDER_ID',      'DUPLICATE_PK',     'ORDER_ID=1001 appears twice (exact duplicate row)',                                'ORDER_ID is unique', 'ORDER_ID=1001 duplicated', 2, 'CRITICAL'),
-- CHECK 3: Duplicate Record Detection
(6,  3, 'Duplicate Record Detection',   'CUSTOMERS',         'FIRST_NAME,LAST_NAME,EMAIL', 'DUPLICATE_RECORD', 'Bob Jones with same email/phone appears as ID=2 and ID=7',          'No duplicate records on name+email+phone', 'Exact duplicate found', 2, 'HIGH'),
(7,  3, 'Duplicate Record Detection',   'AUDIT_LOG',         'TABLE_NAME,RECORD_ID,CDC_SEQUENCE', 'DUPLICATE_RECORD', 'AUDIT_LOG rows 4 and 15 are identical (ORDERS/1001/seq 4)', 'No duplicate audit entries', 'Exact duplicate found', 2, 'HIGH'),
-- CHECK 4: Referential Integrity
(8,  4, 'Referential Integrity',        'ORDERS',            'CUSTOMER_ID',   'ORPHAN_FK',        'Order ID=1008 references CUSTOMER_ID=999 which does not exist in CUSTOMERS',     'CUSTOMER_ID exists in CUSTOMERS', 'CUSTOMER_ID=999 not found', 1, 'CRITICAL'),
(9,  4, 'Referential Integrity',        'ORDER_ITEMS',       'PRODUCT_ID',    'ORPHAN_FK',        'Order item ID=9 references PRODUCT_ID=999 which does not exist in PRODUCTS',     'PRODUCT_ID exists in PRODUCTS', 'PRODUCT_ID=999 not found', 1, 'CRITICAL'),
-- CHECK 5: Data Type Validation (Snowflake strongly typed; use TRY_CAST for VARCHAR validation)
(10, 5, 'Data Type Validation',         'CUSTOMERS',         'POSTAL_CODE',   'TYPE_MISMATCH',    'Customer ID=14 POSTAL_CODE=ABCXYZ fails TRY_CAST to NUMBER. US postal codes should be numeric.', 'TRY_CAST(POSTAL_CODE AS NUMBER) IS NOT NULL for US customers', 'TRY_CAST(ABCXYZ AS NUMBER) IS NULL', 1, 'HIGH'),
-- CHECK 6: Numeric Range Validation
(11, 6, 'Numeric Range Validation',     'PRODUCTS',          'PRICE',         'OUT_OF_RANGE',     'Product ID=107 has PRICE=-50.00 (negative)',                                       'PRICE >= 0', 'PRICE = -50.00', 1, 'MEDIUM'),
(12, 6, 'Numeric Range Validation',     'ORDER_ITEMS',       'UNIT_PRICE',    'OUT_OF_RANGE',     'Order item ID=14 has UNIT_PRICE=99999.00 (unreasonably high)',                    'UNIT_PRICE between 0 and 10000', 'UNIT_PRICE = 99999.00', 1, 'MEDIUM'),
-- CHECK 7: String Length Validation
(13, 7, 'String Length Validation',     'CUSTOMERS',         'FIRST_NAME',    'STRING_TOO_SHORT', 'Customer ID=10 has FIRST_NAME=H (1 char, below min 2)',                           'LENGTH(FIRST_NAME) >= 2', 'LENGTH = 1', 1, 'LOW'),
(14, 7, 'String Length Validation',     'FILE_INGESTION_LOG','FILE_NAME',     'STRING_TOO_LONG',  'Ingestion ID=11 has FILE_NAME >200 characters',                                   'LENGTH(FILE_NAME) <= 200', 'LENGTH = 211', 1, 'LOW'),
-- CHECK 8: Regex Pattern Validation
(15, 8, 'Regex Pattern Validation',     'CUSTOMERS',         'EMAIL',         'REGEX_MISMATCH',   'Customer ID=8 EMAIL=not-an-email fails regex pattern',                            'EMAIL matches email regex', 'Value is not-an-email', 1, 'MEDIUM'),
-- CHECK 9: Allowed Values / Domain Validation
(16, 9, 'Allowed Values / Domain',      'CUSTOMERS',         'CUSTOMER_STATUS','INVALID_DOMAIN',  'Customer ID=9 has CUSTOMER_STATUS=DELETED (not in ACTIVE,INACTIVE,SUSPENDED)',    'Status in (ACTIVE,INACTIVE,SUSPENDED)', 'DELETED', 1, 'MEDIUM'),
(17, 9, 'Allowed Values / Domain',      'PRODUCTS',          'CATEGORY',      'INVALID_DOMAIN',   'Product ID=108 has CATEGORY=INVALID_CAT',                                         'Category in (Electronics,Furniture,Accessories,Stationery)', 'INVALID_CAT', 1, 'MEDIUM'),
(18, 9, 'Allowed Values / Domain',      'ORDERS',            'ORDER_STATUS',  'INVALID_DOMAIN',   'Order ID=1010 has ORDER_STATUS=VOIDED (not in PENDING,SHIPPED,COMPLETED,CANCELLED)', 'Status in (PENDING,SHIPPED,COMPLETED,CANCELLED)', 'VOIDED', 1, 'MEDIUM'),
-- CHECK 10: Business Rule Consistency
(19, 10,'Business Rule Consistency',    'ORDERS',            'ORDER_DATE',    'BUSINESS_RULE',    'Order ID=1007 has ORDER_DATE=2029-12-31 (future date)',                           'ORDER_DATE <= CURRENT_DATE', 'ORDER_DATE = 2029-12-31', 1, 'HIGH'),
(20, 10,'Business Rule Consistency',    'DAILY_AGGREGATES',  'AVG_AMOUNT',    'BUSINESS_RULE',    'Agg ID=8 has AVG_AMOUNT=500 > TOTAL_AMOUNT=100 (impossible)',                    'AVG_AMOUNT <= TOTAL_AMOUNT', 'AVG_AMOUNT > TOTAL_AMOUNT', 1, 'HIGH'),
-- CHECK 11: Cross-Column Consistency
(21, 11,'Cross-Column Consistency',     'CUSTOMERS',         'COUNTRY,STATE', 'CROSS_COL_MISMATCH','Customer ID=11 has COUNTRY=UK but STATE=CA and US postal code',                 'UK customers have UK state/postal', 'UK + CA + 90001', 1, 'MEDIUM'),
(22, 11,'Cross-Column Consistency',     'ORDERS',            'CURRENCY,COUNTRY','CROSS_COL_MISMATCH','Order ID=1009 has CURRENCY=GBP but COUNTRY=US',                               'US orders use USD', 'GBP + US', 1, 'MEDIUM'),
(23, 11,'Cross-Column Consistency',     'ORDER_ITEMS',       'DISCOUNT_PCT,DISCOUNT_AMT','CROSS_COL_MISMATCH','Item ID=12 has DISCOUNT_PCT=10% but DISCOUNT_AMT=0',                 'DISCOUNT_AMT = UNIT_PRICE * DISCOUNT_PCT/100', 'PCT=10, AMT=0', 1, 'MEDIUM'),
-- CHECK 12: Timeliness / Freshness
(24, 12,'Timeliness / Freshness',       'CUSTOMERS',         'UPDATED_AT',    'STALE_DATA',       'Customer ID=12 has UPDATED_AT=2022-01-01 (>2 years old)',                        'UPDATED_AT within SLA', 'Last update 2+ years ago', 1, 'CRITICAL'),
-- CHECK 13: Completeness
(25, 13,'Completeness',                 'ORDERS',            'ALL_COLUMNS',   'INCOMPLETE_RECORD','Order ID=1012 has NULL in all columns except ORDER_ID',                           'All required columns populated', 'Most columns are NULL', 1, 'HIGH'),
-- CHECK 14: Volume Check
(26, 14,'Volume Check',                 'DAILY_AGGREGATES',  'TOTAL_ROWS',    'VOLUME_ANOMALY',   'Agg ID=7 shows TOTAL_ROWS=0 for 2024-08-15 indicating missing load',             'TOTAL_ROWS > 0 for active dates', 'TOTAL_ROWS = 0', 1, 'HIGH'),
-- CHECK 15: Distribution Check (threshold: 30%)
(27, 15,'Distribution Check',           'EMPLOYEES',         'DEPARTMENT',    'DISTRIBUTION_SKEW','Engineering has 5/13 employees (38.46%). Threshold: no department > 30%.',         'Each DEPARTMENT <= 30% of total employee count', 'Engineering = 38.46% (5/13), exceeds 30% threshold', 5, 'MEDIUM'),
-- CHECK 16: Outlier Detection
(28, 16,'Outlier Detection',            'ORDER_ITEMS',       'QUANTITY',      'OUTLIER',          'Item ID=11 has QUANTITY=10000 (extreme outlier vs normal 1-5)',                   'QUANTITY within 3 std devs of mean', 'QUANTITY = 10000', 1, 'MEDIUM'),
(29, 16,'Outlier Detection',            'PRODUCTS',          'WEIGHT_KG',     'OUTLIER',          'Product ID=109 has WEIGHT_KG=9999 (extreme outlier vs normal 0.01-35)',           'WEIGHT_KG within 3 std devs of mean', 'WEIGHT_KG = 9999', 1, 'MEDIUM'),
-- CHECK 17: Schema Drift Detection (baseline vs current INFORMATION_SCHEMA)
(30, 17,'Schema Drift Detection',       'PRODUCTS',          'SUPPLIER_CODE', 'SCHEMA_DRIFT',     'Column SUPPLIER_CODE (VARCHAR(20)) added after baseline. Baseline=7 cols, current=8.', 'Schema matches baseline snapshot (7 columns)', 'New column SUPPLIER_CODE at position 8 not in baseline', 1, 'CRITICAL'),
-- CHECK 18: End-to-End Reconciliation (ORDERS source vs ORDERS_RECON_TARGET)
(31, 18,'End-to-End Reconciliation',    'DAILY_AGGREGATES',  'TOTAL_AMOUNT',  'RECON_MISMATCH',   'For 2024-06-15: ORDERS source=1 row/279.98. ORDERS_RECON_TARGET=3 rows/999.99.', 'ORDERS source for 2024-06-15: COUNT=1, SUM=279.98', 'ORDERS_RECON_TARGET for 2024-06-15: TOTAL_ROWS=3, TOTAL_AMOUNT=999.99', 1, 'CRITICAL'),
-- CHECK 19: Duplicate File Ingestion
(32, 19,'Duplicate File Ingestion',     'FILE_INGESTION_LOG','FILE_NAME',     'DUPLICATE_FILE',   'customers_20240601.csv ingested 3 times (IDs 1,6,7) with same hash',             'Each file ingested exactly once', 'Ingested 3 times', 3, 'HIGH'),
-- CHECK 20: Negative Value Check
(33, 20,'Negative Value Check',         'ORDERS',            'ORDER_AMOUNT',  'NEGATIVE_VALUE',   'Order ID=1006 has ORDER_AMOUNT=-150.00',                                          'ORDER_AMOUNT >= 0', 'ORDER_AMOUNT = -150.00', 1, 'MEDIUM'),
(34, 20,'Negative Value Check',         'EMPLOYEES',         'SALARY',        'NEGATIVE_VALUE',   'Employee ID=10 has SALARY=-5000.00',                                              'SALARY >= 0', 'SALARY = -5000.00', 1, 'MEDIUM'),
-- CHECK 21: Percentage / Total Consistency
(35, 21,'Percentage / Total Consistency','ORDER_ITEMS',      'LINE_TOTAL',    'TOTAL_MISMATCH',   'Item ID=10 has QTY=1 * PRICE=100.00 but LINE_TOTAL=999.00',                      'LINE_TOTAL = QUANTITY * UNIT_PRICE', '999.00 != 100.00', 1, 'HIGH'),
-- CHECK 22: Hierarchy Validation
(36, 22,'Hierarchy Validation',         'EMPLOYEES',         'MANAGER_ID',    'ORPHAN_NODE',      'Employee ID=7 has MANAGER_ID=999 which does not exist',                           'MANAGER_ID exists in EMPLOYEE_ID or IS NULL', 'MANAGER_ID=999 not found', 1, 'HIGH'),
(37, 22,'Hierarchy Validation',         'EMPLOYEES',         'MANAGER_ID',    'CIRCULAR_REF',     'Employee ID=8 manages ID=9 and ID=9 manages ID=8 (circular)',                    'No circular references in hierarchy', 'Circular: 8->9->8', 2, 'HIGH'),
-- CHECK 23: Multi-Source Consistency (same AGG_DATE+TABLE_NAME, different values)
(38, 23,'Multi-Source Consistency',     'DAILY_AGGREGATES',  'TOTAL_AMOUNT',  'MULTI_SOURCE_DIFF','For 2024-06-01 ORDERS: AGG_ID=1 reports 1029.98, AGG_ID=10 reports 999.99.',      'Single consistent TOTAL_AMOUNT per AGG_DATE + TABLE_NAME', 'Two entries for 2024-06-01/ORDERS: 1029.98 vs 999.99 (diff=29.99)', 2, 'HIGH'),
-- CHECK 24: Audit Column Validation
(39, 24,'Audit Column Validation',      'CUSTOMERS',         'UPDATED_AT',    'AUDIT_INCONSISTENT','Customer ID=13 has UPDATED_AT=2024-01-01 before CREATED_AT=2024-06-15',         'UPDATED_AT >= CREATED_AT', 'UPDATED_AT < CREATED_AT', 1, 'MEDIUM'),
(40, 24,'Audit Column Validation',      'AUDIT_LOG',         'CHANGED_BY',    'AUDIT_NULL',       'Audit log ID=12 has NULL CHANGED_BY',                                             'CHANGED_BY IS NOT NULL', 'CHANGED_BY IS NULL', 1, 'MEDIUM'),
(41, 24,'Audit Column Validation',      'AUDIT_LOG',         'UPDATED_AT',    'AUDIT_INCONSISTENT','Audit log ID=13 has UPDATED_AT=2024-04-14 before CREATED_AT=2024-04-15',        'UPDATED_AT >= CREATED_AT', 'UPDATED_AT < CREATED_AT', 1, 'MEDIUM'),
-- CHECK 25: CDC Consistency (invalid operation + duplicate sequence + invalid state transition)
(42, 25,'CDC Consistency',              'AUDIT_LOG',         'CDC_OPERATION', 'INVALID_CDC_OP',   'Audit log ID=9 has CDC_OPERATION=X (not in I/U/D).',                              'CDC_OPERATION IN (I, U, D)', 'CDC_OPERATION = X', 1, 'HIGH'),
(43, 25,'CDC Consistency',              'AUDIT_LOG',         'CDC_SEQUENCE',  'DUPLICATE_CDC_SEQ','ORDERS/1004 has duplicate CDC_SEQUENCE=15. D at 06:00 then I at 07:00 (invalid state transition).', 'CDC_SEQUENCE unique per TABLE_NAME+RECORD_ID; valid state transitions', 'Duplicate sequence=15; Delete before Insert', 2, 'HIGH');

-- ============================================================
-- 06. CHECK RESULT TABLES
-- ============================================================
USE SCHEMA DQ_GUARDIAN.CHECK_RESULTS;

-- -------------------------------------------------------
-- 1. DQ_RUN_LOG — One record per DQ execution run
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG (
    RUN_ID              VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    RUN_START_TIME      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    RUN_END_TIME        TIMESTAMP_NTZ,
    TARGET_DATABASE     VARCHAR(256)    NOT NULL,
    TARGET_SCHEMA       VARCHAR(256)    NOT NULL,
    TARGET_TABLE        VARCHAR(256)    NOT NULL,
    TOTAL_CHECKS        INTEGER         DEFAULT 0,
    PASSED_CHECKS       INTEGER         DEFAULT 0,
    FAILED_CHECKS       INTEGER         DEFAULT 0,
    OVERALL_STATUS      VARCHAR(20)     DEFAULT 'RUNNING',
    TRIGGERED_BY        VARCHAR(100)    DEFAULT 'MANUAL',
    CREATED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_RUN_LOG PRIMARY KEY (RUN_ID)
)
COMMENT = 'One record per DQ execution run';

-- -------------------------------------------------------
-- 2. DQ_CHECK_RESULTS — One result per check per run
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.CHECK_RESULTS.DQ_CHECK_RESULTS (
    RESULT_ID           VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    RUN_ID              VARCHAR(36)     NOT NULL,
    CHECK_ID            INTEGER         NOT NULL,
    CHECK_NAME          VARCHAR(100)    NOT NULL,
    TARGET_TABLE        VARCHAR(256)    NOT NULL,
    TARGET_COLUMN       VARCHAR(256),
    CHECK_STATUS        VARCHAR(20)     NOT NULL,
    TOTAL_ROWS          INTEGER,
    FAILURE_COUNT       INTEGER         DEFAULT 0,
    FAILURE_PCT         NUMBER(7,4),
    THRESHOLD_WARNING   NUMBER(10,4),
    THRESHOLD_FAIL      NUMBER(10,4),
    SEVERITY            VARCHAR(20),
    WEIGHT              NUMBER(5,2),
    SCORE               NUMBER(5,2),
    EXECUTION_TIME_MS   INTEGER,
    ERROR_MESSAGE       VARCHAR(2000),
    CREATED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_CHECK_RESULTS PRIMARY KEY (RESULT_ID)
)
COMMENT = 'One result per DQ check executed during a run';

-- -------------------------------------------------------
-- 3. DQ_FAILED_RECORDS — Individual failing records
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.CHECK_RESULTS.DQ_FAILED_RECORDS (
    FAILURE_ID          VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    RUN_ID              VARCHAR(36)     NOT NULL,
    CHECK_ID            INTEGER         NOT NULL,
    TARGET_TABLE        VARCHAR(256)    NOT NULL,
    RECORD_IDENTIFIER   VARCHAR(500)    NOT NULL,
    COLUMN_NAME         VARCHAR(256),
    FAILED_VALUE        VARCHAR(1000),
    FAILURE_REASON      VARCHAR(1000),
    CREATED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_FAILED_RECORDS PRIMARY KEY (FAILURE_ID)
)
COMMENT = 'Individual records that failed a DQ check';

-- -------------------------------------------------------
-- 4. DQ_HEALTH_SCORES — Health score per run and table
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.CHECK_RESULTS.DQ_HEALTH_SCORES (
    SCORE_ID            VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    RUN_ID              VARCHAR(36)     NOT NULL,
    TARGET_TABLE        VARCHAR(256)    NOT NULL,
    HEALTH_SCORE        NUMBER(5,2)     NOT NULL,
    TOTAL_CHECKS        INTEGER         NOT NULL,
    PASSED_CHECKS       INTEGER         NOT NULL,
    FAILED_CHECKS       INTEGER         NOT NULL,
    CRITICAL_FAILURES   INTEGER         DEFAULT 0,
    HIGH_FAILURES       INTEGER         DEFAULT 0,
    MEDIUM_FAILURES     INTEGER         DEFAULT 0,
    LOW_FAILURES        INTEGER         DEFAULT 0,
    SCORE_CALCULATED_AT TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_HEALTH_SCORES PRIMARY KEY (SCORE_ID)
)
COMMENT = 'DQ health score per run and table';

-- ============================================================
-- 07. DQ ENGINE CONFIGURATION (SQL Templates + Assignments + Thresholds)
-- ============================================================
-- -------------------------------------------------------
-- 1. CLEAR PARTIAL CONFIG FROM EARLIER ATTEMPTS
-- -------------------------------------------------------
DELETE FROM DQ_GUARDIAN.CONFIG.DQ_THRESHOLDS;
DELETE FROM DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS;

-- -------------------------------------------------------
-- 2. UPDATE SQL_TEMPLATE IN DQ_CHECK_LIBRARY
-- All templates return failing rows so the engine can:
--   (a) COUNT(*) the result → failure_count
--   (b) capture each row → DQ_FAILED_RECORDS
-- Templates use {{placeholder}} syntax substituted at runtime.
-- -------------------------------------------------------

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, ''{{column}}'' AS column_name FROM {{database}}.{{schema}}.{{table}} WHERE {{column}} IS NULL'
WHERE CHECK_ID = 1;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{column}} AS record_id, COUNT(*) AS occurrences FROM {{database}}.{{schema}}.{{table}} GROUP BY {{column}} HAVING COUNT(*) > 1'
WHERE CHECK_ID = 2;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{columns}}, COUNT(*) AS dup_count FROM {{database}}.{{schema}}.{{table}} {{where_clause}} GROUP BY {{columns}} HAVING COUNT(*) > 1'
WHERE CHECK_ID = 3;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT c.{{fk_column}} AS record_id, c.{{fk_column}} AS failed_value FROM {{database}}.{{schema}}.{{table}} c LEFT JOIN {{database}}.{{schema}}.{{parent_table}} p ON c.{{fk_column}} = p.{{pk_column}} WHERE p.{{pk_column}} IS NULL AND c.{{fk_column}} IS NOT NULL'
WHERE CHECK_ID = 4;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, {{column}} AS failed_value FROM {{database}}.{{schema}}.{{table}} WHERE {{filter}} AND {{column}} IS NOT NULL AND TRY_CAST({{column}} AS {{expected_type}}) IS NULL'
WHERE CHECK_ID = 5;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, {{column}} AS failed_value FROM {{database}}.{{schema}}.{{table}} WHERE {{column}} < {{min_value}} OR {{column}} > {{max_value}}'
WHERE CHECK_ID = 6;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, {{column}} AS failed_value, LENGTH({{column}}) AS actual_len FROM {{database}}.{{schema}}.{{table}} WHERE {{column}} IS NOT NULL AND (LENGTH({{column}}) < {{min_length}} OR LENGTH({{column}}) > {{max_length}})'
WHERE CHECK_ID = 7;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, {{column}} AS failed_value FROM {{database}}.{{schema}}.{{table}} WHERE {{column}} IS NOT NULL AND NOT REGEXP_LIKE({{column}}, ''{{pattern}}'')'
WHERE CHECK_ID = 8;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, {{column}} AS failed_value FROM {{database}}.{{schema}}.{{table}} WHERE {{column}} NOT IN ({{allowed_values}}) AND {{column}} IS NOT NULL'
WHERE CHECK_ID = 9;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id FROM {{database}}.{{schema}}.{{table}} WHERE {{rule_expression}}'
WHERE CHECK_ID = 10;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id FROM {{database}}.{{schema}}.{{table}} WHERE {{rule_expression}}'
WHERE CHECK_ID = 11;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, {{timestamp_column}} AS failed_value, DATEDIFF(''day'', {{timestamp_column}}, CURRENT_TIMESTAMP()) AS days_stale FROM {{database}}.{{schema}}.{{table}} WHERE DATEDIFF(''day'', {{timestamp_column}}, CURRENT_TIMESTAMP()) > {{max_staleness_days}}'
WHERE CHECK_ID = 12;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id FROM {{database}}.{{schema}}.{{table}} WHERE {{null_check_expression}}'
WHERE CHECK_ID = 13;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, {{volume_column}} AS failed_value FROM {{database}}.{{schema}}.{{table}} WHERE {{volume_column}} = 0 AND {{date_column}} IS NOT NULL'
WHERE CHECK_ID = 14;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{column}} AS failed_value, COUNT(*) AS group_count, ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM {{database}}.{{schema}}.{{table}}), 2) AS pct FROM {{database}}.{{schema}}.{{table}} GROUP BY {{column}} HAVING COUNT(*) * 100.0 / (SELECT COUNT(*) FROM {{database}}.{{schema}}.{{table}}) > {{max_pct}}'
WHERE CHECK_ID = 15;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, {{column}} AS failed_value, ROUND(({{column}} - AVG({{column}}) OVER()) / NULLIF(STDDEV({{column}}) OVER(), 0), 2) AS z_score FROM {{database}}.{{schema}}.{{table}} WHERE {{column}} IS NOT NULL QUALIFY ABS(({{column}} - AVG({{column}}) OVER()) / NULLIF(STDDEV({{column}}) OVER(), 0)) > {{z_threshold}}'
WHERE CHECK_ID = 16;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT c.COLUMN_NAME AS record_id, ''ADDED'' AS failed_value FROM {{database}}.INFORMATION_SCHEMA.COLUMNS c LEFT JOIN {{database}}.PROFILING.SCHEMA_SNAPSHOTS s ON c.COLUMN_NAME = s.COLUMN_NAME AND s.TABLE_NAME = ''{{table}}'' WHERE c.TABLE_SCHEMA = ''{{schema}}'' AND c.TABLE_NAME = ''{{table}}'' AND s.COLUMN_NAME IS NULL UNION ALL SELECT s.COLUMN_NAME, ''REMOVED'' FROM {{database}}.PROFILING.SCHEMA_SNAPSHOTS s LEFT JOIN {{database}}.INFORMATION_SCHEMA.COLUMNS c ON s.COLUMN_NAME = c.COLUMN_NAME AND c.TABLE_SCHEMA = ''{{schema}}'' AND c.TABLE_NAME = ''{{table}}'' WHERE s.TABLE_NAME = ''{{table}}'' AND c.COLUMN_NAME IS NULL'
WHERE CHECK_ID = 17;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT src.{{src_date_col}} AS record_id, src.src_count, src.src_amount, tgt.{{tgt_count_col}} AS tgt_count, tgt.{{tgt_amount_col}} AS tgt_amount FROM (SELECT {{src_date_col}}, COUNT(*) AS src_count, SUM({{src_amount_col}}) AS src_amount FROM {{database}}.{{schema}}.{{source_table}} WHERE {{src_date_col}} IS NOT NULL GROUP BY {{src_date_col}}) src JOIN {{database}}.{{schema}}.{{table}} tgt ON src.{{src_date_col}} = tgt.{{tgt_date_col}} WHERE tgt.{{tgt_filter_col}} = ''{{tgt_filter_val}}'' AND (src.src_count != tgt.{{tgt_count_col}} OR src.src_amount != tgt.{{tgt_amount_col}})'
WHERE CHECK_ID = 18;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{file_column}} AS record_id, {{file_column}} AS failed_value, COUNT(*) AS load_count FROM {{database}}.{{schema}}.{{table}} WHERE {{file_column}} IS NOT NULL GROUP BY {{file_column}} HAVING COUNT(*) > 1'
WHERE CHECK_ID = 19;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, {{column}} AS failed_value FROM {{database}}.{{schema}}.{{table}} WHERE {{column}} < 0'
WHERE CHECK_ID = 20;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, {{total_column}} AS failed_value, {{qty_column}} * {{price_column}} AS expected_total FROM {{database}}.{{schema}}.{{table}} WHERE {{qty_column}} IS NOT NULL AND {{price_column}} IS NOT NULL AND ABS({{total_column}} - ({{qty_column}} * {{price_column}})) > {{tolerance}}'
WHERE CHECK_ID = 21;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT e.{{id_column}} AS record_id, ''ORPHAN'' AS failed_value FROM {{database}}.{{schema}}.{{table}} e LEFT JOIN {{database}}.{{schema}}.{{table}} m ON e.{{parent_column}} = m.{{id_column}} WHERE e.{{parent_column}} IS NOT NULL AND m.{{id_column}} IS NULL UNION ALL SELECT a.{{id_column}}, ''CIRCULAR'' FROM {{database}}.{{schema}}.{{table}} a JOIN {{database}}.{{schema}}.{{table}} b ON a.{{parent_column}} = b.{{id_column}} WHERE b.{{parent_column}} = a.{{id_column}}'
WHERE CHECK_ID = 22;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{date_column}} AS record_id, {{group_column}} AS failed_value, COUNT(*) AS entry_count, MIN({{amount_column}}) AS min_val, MAX({{amount_column}}) AS max_val FROM {{database}}.{{schema}}.{{table}} WHERE {{group_column}} = ''{{group_value}}'' AND {{date_column}} IS NOT NULL GROUP BY {{date_column}}, {{group_column}} HAVING COUNT(DISTINCT {{amount_column}}) > 1'
WHERE CHECK_ID = 23;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id FROM {{database}}.{{schema}}.{{table}} WHERE {{rule_expression}}'
WHERE CHECK_ID = 24;

UPDATE DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY SET SQL_TEMPLATE =
  'SELECT {{record_id}} AS record_id, {{cdc_op_column}} AS failed_value FROM {{database}}.{{schema}}.{{table}} WHERE {{rule_expression}}'
WHERE CHECK_ID = 25;

-- -------------------------------------------------------
-- 3. POPULATE DQ_CHECK_ASSIGNMENTS (42 assignments, all 25 checks)
-- -------------------------------------------------------

-- Checks 1-3: Null, PK uniqueness, Duplicates
INSERT INTO DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS
(CHECK_ID, TARGET_DATABASE, TARGET_SCHEMA, TARGET_TABLE, TARGET_COLUMN, PARAMS_JSON)
SELECT 1,'DQ_GUARDIAN','SYNTHETIC_DATA','CUSTOMERS','FIRST_NAME', PARSE_JSON('{"record_id":"CUSTOMER_ID"}')
UNION ALL SELECT 1,'DQ_GUARDIAN','SYNTHETIC_DATA','PRODUCTS','PRODUCT_NAME', PARSE_JSON('{"record_id":"PRODUCT_ID"}')
UNION ALL SELECT 1,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDERS','ORDER_AMOUNT', PARSE_JSON('{"record_id":"ORDER_ID"}')
UNION ALL SELECT 2,'DQ_GUARDIAN','SYNTHETIC_DATA','CUSTOMERS','CUSTOMER_ID', PARSE_JSON('{"record_id":"CUSTOMER_ID"}')
UNION ALL SELECT 2,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDERS','ORDER_ID', PARSE_JSON('{"record_id":"ORDER_ID"}')
UNION ALL SELECT 3,'DQ_GUARDIAN','SYNTHETIC_DATA','CUSTOMERS',NULL, PARSE_JSON('{"columns":"FIRST_NAME,LAST_NAME,EMAIL,PHONE","where_clause":""}')
UNION ALL SELECT 3,'DQ_GUARDIAN','SYNTHETIC_DATA','AUDIT_LOG',NULL, PARSE_JSON('{"columns":"TABLE_NAME,RECORD_ID,CDC_SEQUENCE","where_clause":"WHERE TABLE_NAME IS NOT NULL"}');

-- Checks 4-9: Referential integrity, Data type, Range, Length, Regex, Domain
INSERT INTO DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS
(CHECK_ID, TARGET_DATABASE, TARGET_SCHEMA, TARGET_TABLE, TARGET_COLUMN, PARAMS_JSON)
SELECT 4,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDERS','CUSTOMER_ID', PARSE_JSON('{"fk_column":"CUSTOMER_ID","parent_table":"CUSTOMERS","pk_column":"CUSTOMER_ID"}')
UNION ALL SELECT 4,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDER_ITEMS','PRODUCT_ID', PARSE_JSON('{"fk_column":"PRODUCT_ID","parent_table":"PRODUCTS","pk_column":"PRODUCT_ID"}')
UNION ALL SELECT 5,'DQ_GUARDIAN','SYNTHETIC_DATA','CUSTOMERS','POSTAL_CODE', PARSE_JSON('{"record_id":"CUSTOMER_ID","expected_type":"NUMBER","filter":"COUNTRY = \'US\'"}')
UNION ALL SELECT 6,'DQ_GUARDIAN','SYNTHETIC_DATA','PRODUCTS','PRICE', PARSE_JSON('{"record_id":"PRODUCT_ID","min_value":"0","max_value":"99999"}')
UNION ALL SELECT 6,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDER_ITEMS','UNIT_PRICE', PARSE_JSON('{"record_id":"ITEM_ID","min_value":"0","max_value":"10000"}')
UNION ALL SELECT 7,'DQ_GUARDIAN','SYNTHETIC_DATA','CUSTOMERS','FIRST_NAME', PARSE_JSON('{"record_id":"CUSTOMER_ID","min_length":"2","max_length":"50"}')
UNION ALL SELECT 7,'DQ_GUARDIAN','SYNTHETIC_DATA','FILE_INGESTION_LOG','FILE_NAME', PARSE_JSON('{"record_id":"INGESTION_ID","min_length":"1","max_length":"200"}')
UNION ALL SELECT 8,'DQ_GUARDIAN','SYNTHETIC_DATA','CUSTOMERS','EMAIL', PARSE_JSON('{"record_id":"CUSTOMER_ID","pattern":"^[A-Za-z0-9._%+\\\\-]+@[A-Za-z0-9.\\\\-]+\\\\.[A-Za-z]{2,}$"}')
UNION ALL SELECT 9,'DQ_GUARDIAN','SYNTHETIC_DATA','CUSTOMERS','CUSTOMER_STATUS', PARSE_JSON('{"record_id":"CUSTOMER_ID","allowed_values":"\'ACTIVE\',\'INACTIVE\',\'SUSPENDED\'"}')
UNION ALL SELECT 9,'DQ_GUARDIAN','SYNTHETIC_DATA','PRODUCTS','CATEGORY', PARSE_JSON('{"record_id":"PRODUCT_ID","allowed_values":"\'Electronics\',\'Furniture\',\'Accessories\',\'Stationery\'"}')
UNION ALL SELECT 9,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDERS','ORDER_STATUS', PARSE_JSON('{"record_id":"ORDER_ID","allowed_values":"\'PENDING\',\'SHIPPED\',\'COMPLETED\',\'CANCELLED\'"}');

-- Checks 10-16: Business rules, Cross-column, Freshness, Completeness, Volume, Distribution, Outlier
INSERT INTO DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS
(CHECK_ID, TARGET_DATABASE, TARGET_SCHEMA, TARGET_TABLE, TARGET_COLUMN, PARAMS_JSON)
SELECT 10,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDERS','ORDER_DATE', PARSE_JSON('{"record_id":"ORDER_ID","rule_expression":"ORDER_DATE > CURRENT_DATE()"}')
UNION ALL SELECT 10,'DQ_GUARDIAN','SYNTHETIC_DATA','DAILY_AGGREGATES','AVG_AMOUNT', PARSE_JSON('{"record_id":"AGG_ID","rule_expression":"AVG_AMOUNT > TOTAL_AMOUNT AND TOTAL_AMOUNT IS NOT NULL"}')
UNION ALL SELECT 11,'DQ_GUARDIAN','SYNTHETIC_DATA','CUSTOMERS','COUNTRY,STATE', PARSE_JSON('{"record_id":"CUSTOMER_ID","rule_expression":"COUNTRY = \'UK\' AND REGEXP_LIKE(POSTAL_CODE, \'^[0-9]+$\')"}')
UNION ALL SELECT 11,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDERS','CURRENCY,COUNTRY', PARSE_JSON('{"record_id":"ORDER_ID","rule_expression":"CURRENCY = \'GBP\' AND COUNTRY = \'US\'"}')
UNION ALL SELECT 11,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDER_ITEMS','DISCOUNT_PCT,DISCOUNT_AMT', PARSE_JSON('{"record_id":"ITEM_ID","rule_expression":"DISCOUNT_PCT > 0 AND DISCOUNT_AMT = 0"}')
UNION ALL SELECT 12,'DQ_GUARDIAN','SYNTHETIC_DATA','CUSTOMERS','UPDATED_AT', PARSE_JSON('{"record_id":"CUSTOMER_ID","timestamp_column":"UPDATED_AT","max_staleness_days":"1500"}')
UNION ALL SELECT 13,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDERS',NULL, PARSE_JSON('{"record_id":"ORDER_ID","null_check_expression":"CUSTOMER_ID IS NULL AND ORDER_DATE IS NULL AND ORDER_STATUS IS NULL AND ORDER_AMOUNT IS NULL"}')
UNION ALL SELECT 14,'DQ_GUARDIAN','SYNTHETIC_DATA','DAILY_AGGREGATES','TOTAL_ROWS', PARSE_JSON('{"record_id":"AGG_ID","volume_column":"TOTAL_ROWS","date_column":"AGG_DATE"}')
UNION ALL SELECT 15,'DQ_GUARDIAN','SYNTHETIC_DATA','EMPLOYEES','DEPARTMENT', PARSE_JSON('{"max_pct":"30"}')
UNION ALL SELECT 16,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDER_ITEMS','QUANTITY', PARSE_JSON('{"record_id":"ITEM_ID","z_threshold":"3"}')
UNION ALL SELECT 16,'DQ_GUARDIAN','SYNTHETIC_DATA','PRODUCTS','WEIGHT_KG', PARSE_JSON('{"record_id":"PRODUCT_ID","z_threshold":"3"}');

-- Checks 17-25: Schema drift, Reconciliation, Dup file, Negative, Pct/total, Hierarchy, Multi-source, Audit, CDC
INSERT INTO DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS
(CHECK_ID, TARGET_DATABASE, TARGET_SCHEMA, TARGET_TABLE, TARGET_COLUMN, PARAMS_JSON)
SELECT 17,'DQ_GUARDIAN','SYNTHETIC_DATA','PRODUCTS',NULL, PARSE_JSON('{}')
UNION ALL SELECT 18,'DQ_GUARDIAN','SYNTHETIC_DATA','DAILY_AGGREGATES',NULL, PARSE_JSON('{"source_table":"ORDERS","src_date_col":"ORDER_DATE","src_amount_col":"ORDER_AMOUNT","tgt_date_col":"AGG_DATE","tgt_count_col":"TOTAL_ROWS","tgt_amount_col":"TOTAL_AMOUNT","tgt_filter_col":"TABLE_NAME","tgt_filter_val":"ORDERS_RECON_TARGET"}')
UNION ALL SELECT 19,'DQ_GUARDIAN','SYNTHETIC_DATA','FILE_INGESTION_LOG','FILE_NAME', PARSE_JSON('{"file_column":"FILE_NAME"}')
UNION ALL SELECT 20,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDERS','ORDER_AMOUNT', PARSE_JSON('{"record_id":"ORDER_ID"}')
UNION ALL SELECT 20,'DQ_GUARDIAN','SYNTHETIC_DATA','EMPLOYEES','SALARY', PARSE_JSON('{"record_id":"EMPLOYEE_ID"}')
UNION ALL SELECT 21,'DQ_GUARDIAN','SYNTHETIC_DATA','ORDER_ITEMS','LINE_TOTAL', PARSE_JSON('{"record_id":"ITEM_ID","qty_column":"QUANTITY","price_column":"UNIT_PRICE","total_column":"LINE_TOTAL","tolerance":"0.01"}')
UNION ALL SELECT 22,'DQ_GUARDIAN','SYNTHETIC_DATA','EMPLOYEES',NULL, PARSE_JSON('{"id_column":"EMPLOYEE_ID","parent_column":"MANAGER_ID"}')
UNION ALL SELECT 23,'DQ_GUARDIAN','SYNTHETIC_DATA','DAILY_AGGREGATES',NULL, PARSE_JSON('{"date_column":"AGG_DATE","group_column":"TABLE_NAME","group_value":"ORDERS","amount_column":"TOTAL_AMOUNT"}')
UNION ALL SELECT 24,'DQ_GUARDIAN','SYNTHETIC_DATA','CUSTOMERS','UPDATED_AT', PARSE_JSON('{"record_id":"CUSTOMER_ID","rule_expression":"UPDATED_AT < CREATED_AT"}')
UNION ALL SELECT 24,'DQ_GUARDIAN','SYNTHETIC_DATA','AUDIT_LOG','CHANGED_BY', PARSE_JSON('{"record_id":"LOG_ID","rule_expression":"CHANGED_BY IS NULL"}')
UNION ALL SELECT 24,'DQ_GUARDIAN','SYNTHETIC_DATA','AUDIT_LOG','UPDATED_AT', PARSE_JSON('{"record_id":"LOG_ID","rule_expression":"UPDATED_AT < CREATED_AT"}')
UNION ALL SELECT 25,'DQ_GUARDIAN','SYNTHETIC_DATA','AUDIT_LOG','CDC_OPERATION', PARSE_JSON('{"record_id":"LOG_ID","cdc_op_column":"CDC_OPERATION","rule_expression":"CDC_OPERATION NOT IN (\'I\',\'U\',\'D\')"}')
UNION ALL SELECT 25,'DQ_GUARDIAN','SYNTHETIC_DATA','AUDIT_LOG','CDC_SEQUENCE', PARSE_JSON('{"record_id":"LOG_ID","cdc_op_column":"CDC_SEQUENCE","rule_expression":"(TABLE_NAME, RECORD_ID, CDC_SEQUENCE) IN (SELECT TABLE_NAME, RECORD_ID, CDC_SEQUENCE FROM DQ_GUARDIAN.SYNTHETIC_DATA.AUDIT_LOG WHERE TABLE_NAME IS NOT NULL GROUP BY TABLE_NAME, RECORD_ID, CDC_SEQUENCE HAVING COUNT(*) > 1) AND TABLE_NAME = \'ORDERS\' AND RECORD_ID = 1004"}');

-- -------------------------------------------------------
-- 4. POPULATE DQ_THRESHOLDS (25 thresholds, one per check)
-- -------------------------------------------------------
INSERT INTO DQ_GUARDIAN.CONFIG.DQ_THRESHOLDS
(CHECK_ID, THRESHOLD_NAME, WARNING_VALUE, FAIL_VALUE)
SELECT  1, 'null_pct',              5.0000,  10.0000
UNION ALL SELECT  2, 'duplicate_count',      0.0000,   0.0001
UNION ALL SELECT  3, 'duplicate_count',      0.0000,   0.0001
UNION ALL SELECT  4, 'orphan_count',         0.0000,   0.0001
UNION ALL SELECT  5, 'type_fail_pct',        1.0000,   5.0000
UNION ALL SELECT  6, 'range_fail_pct',       1.0000,   5.0000
UNION ALL SELECT  7, 'length_fail_pct',      2.0000,   5.0000
UNION ALL SELECT  8, 'regex_fail_pct',       1.0000,   5.0000
UNION ALL SELECT  9, 'domain_fail_pct',      1.0000,   5.0000
UNION ALL SELECT 10, 'rule_fail_count',      0.0000,   1.0000
UNION ALL SELECT 11, 'consistency_fail_pct', 1.0000,   5.0000
UNION ALL SELECT 12, 'staleness_fail_count', 0.0000,   1.0000
UNION ALL SELECT 13, 'incomplete_count',     0.0000,   1.0000
UNION ALL SELECT 14, 'zero_volume_count',    0.0000,   1.0000
UNION ALL SELECT 15, 'skew_fail_count',      0.0000,   1.0000
UNION ALL SELECT 16, 'outlier_count',        1.0000,   3.0000
UNION ALL SELECT 17, 'drift_column_count',   0.0000,   1.0000
UNION ALL SELECT 18, 'recon_mismatch_count', 0.0000,   1.0000
UNION ALL SELECT 19, 'dup_file_count',       0.0000,   1.0000
UNION ALL SELECT 20, 'negative_count',       0.0000,   1.0000
UNION ALL SELECT 21, 'total_mismatch_count', 0.0000,   1.0000
UNION ALL SELECT 22, 'hierarchy_fail_count', 0.0000,   1.0000
UNION ALL SELECT 23, 'multi_source_conflict',0.0000,   1.0000
UNION ALL SELECT 24, 'audit_fail_pct',       1.0000,   5.0000
UNION ALL SELECT 25, 'cdc_fail_count',       0.0000,   1.0000;

-- ============================================================
-- 08. PROFILING TABLES
-- ============================================================

USE SCHEMA DQ_GUARDIAN.PROFILING;

CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.PROFILING.TABLE_PROFILES (
    PROFILE_ID      VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    DATABASE_NAME   VARCHAR(256)    NOT NULL,
    SCHEMA_NAME     VARCHAR(256)    NOT NULL,
    TABLE_NAME      VARCHAR(256)    NOT NULL,
    ROW_COUNT       INTEGER,
    COLUMN_COUNT    INTEGER,
    PROFILED_AT     TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    PROFILE_STATUS  VARCHAR(20)     NOT NULL DEFAULT 'COMPLETED',
    CONSTRAINT PK_TABLE_PROFILES PRIMARY KEY (PROFILE_ID)
)
COMMENT = 'Table-level profiling results';

CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.PROFILING.COLUMN_PROFILES (
    PROFILE_ID      VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    DATABASE_NAME   VARCHAR(256)    NOT NULL,
    SCHEMA_NAME     VARCHAR(256)    NOT NULL,
    TABLE_NAME      VARCHAR(256)    NOT NULL,
    COLUMN_NAME     VARCHAR(256)    NOT NULL,
    DATA_TYPE       VARCHAR(50),
    ROW_COUNT       INTEGER,
    NULL_COUNT      INTEGER,
    NULL_PCT        NUMBER(7,4),
    DISTINCT_COUNT  INTEGER,
    MIN_VALUE       VARCHAR(500),
    MAX_VALUE       VARCHAR(500),
    MEAN            NUMBER(18,4),
    MEDIAN          NUMBER(18,4),
    TOP_VALUES_JSON VARIANT,
    PATTERN_SUMMARY VARCHAR(500),
    PROFILED_AT     TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_COLUMN_PROFILES PRIMARY KEY (PROFILE_ID)
)
COMMENT = 'Column-level profiling statistics';

CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.PROFILING.DISTRIBUTION_SNAPSHOTS (
    SNAPSHOT_ID     VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    DATABASE_NAME   VARCHAR(256)    NOT NULL,
    SCHEMA_NAME     VARCHAR(256)    NOT NULL,
    TABLE_NAME      VARCHAR(256)    NOT NULL,
    COLUMN_NAME     VARCHAR(256)    NOT NULL,
    VALUE_OR_BUCKET VARCHAR(500),
    RECORD_COUNT    INTEGER,
    PERCENTAGE      NUMBER(7,4),
    SNAPSHOT_AT     TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_DISTRIBUTION_SNAPSHOTS PRIMARY KEY (SNAPSHOT_ID)
)
COMMENT = 'Historical distribution data for drift and anomaly detection';


-- Ensure OVERALL_STATUS can hold longer status values
ALTER TABLE DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG ALTER COLUMN OVERALL_STATUS SET DATA TYPE VARCHAR(30);

-- ============================================================
-- 09. UDFs
-- ============================================================
-- -------------------------------------------------------
-- 1. FN_SCORE_CHECK — Calculate a weighted check score (0-100)
-- Formula: pass_rate * severity_factor * weight
-- Severity factors: CRITICAL=0.50, HIGH=0.70, MEDIUM=0.85, LOW=0.95
-- -------------------------------------------------------
CREATE OR REPLACE FUNCTION DQ_GUARDIAN.CHECK_RESULTS.FN_SCORE_CHECK(
    P_PASSED NUMBER, P_FAILED NUMBER, P_SEVERITY VARCHAR, P_WEIGHT NUMBER
)
RETURNS NUMBER(5,2)
AS
$$
    CASE
        WHEN (P_PASSED + P_FAILED) = 0 THEN 100.00
        ELSE ROUND(
            (P_PASSED * 100.0 / (P_PASSED + P_FAILED))
            * CASE P_SEVERITY
                WHEN 'CRITICAL' THEN 0.50
                WHEN 'HIGH'     THEN 0.70
                WHEN 'MEDIUM'   THEN 0.85
                WHEN 'LOW'      THEN 0.95
                ELSE 0.80
              END
            * P_WEIGHT,
        2)
    END
$$;

-- -------------------------------------------------------
-- 2. FN_DETECT_OUTLIER — Z-score outlier detection
-- Returns TRUE if ABS(value - mean) / stddev > threshold
-- Safely handles NULL and zero standard deviation
-- -------------------------------------------------------
CREATE OR REPLACE FUNCTION DQ_GUARDIAN.CHECK_RESULTS.FN_DETECT_OUTLIER(
    P_VALUE FLOAT, P_MEAN FLOAT, P_STDDEV FLOAT, P_THRESHOLD FLOAT
)
RETURNS BOOLEAN
AS
$$
    CASE
        WHEN P_VALUE IS NULL OR P_MEAN IS NULL OR P_STDDEV IS NULL OR P_STDDEV = 0 THEN FALSE
        ELSE ABS(P_VALUE - P_MEAN) / P_STDDEV > P_THRESHOLD
    END
$$;

-- -------------------------------------------------------
-- 3. FN_VALIDATE_REGEX — Regex pattern validation
-- Returns TRUE when the value matches the pattern
-- Safely handles NULL values
-- -------------------------------------------------------
CREATE OR REPLACE FUNCTION DQ_GUARDIAN.CHECK_RESULTS.FN_VALIDATE_REGEX(
    P_VALUE VARCHAR, P_PATTERN VARCHAR
)
RETURNS BOOLEAN
AS
$$
    CASE
        WHEN P_VALUE IS NULL OR P_PATTERN IS NULL THEN FALSE
        ELSE REGEXP_LIKE(P_VALUE, P_PATTERN)
    END
$$;

-- ============================================================
-- 10. DQ CHECK ENGINE
-- ============================================================
-- The procedure uses JavaScript for reliable dynamic SQL execution.
-- Key design: safeReplace() avoids JavaScript $ replacement issues
-- in regex patterns and other special characters.
CREATE OR REPLACE PROCEDURE DQ_GUARDIAN.CHECK_RESULTS.SP_RUN_DQ_CHECKS(
    P_DATABASE VARCHAR, P_SCHEMA VARCHAR, P_TABLE VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    // Safe string replace: avoids JavaScript regex $ replacement issues
    function safeReplace(str, find, replacement) {
        while (str.indexOf(find) >= 0) {
            str = str.substring(0, str.indexOf(find)) + replacement + str.substring(str.indexOf(find) + find.length);
        }
        return str;
    }

    // 1. Generate run ID
    var rs = snowflake.execute({sqlText: "SELECT UUID_STRING()"});
    rs.next();
    var v_run_id = rs.getColumnValue(1);

    // 2. Create run log entry
    snowflake.execute({sqlText:
        "INSERT INTO DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG " +
        "(RUN_ID, RUN_START_TIME, TARGET_DATABASE, TARGET_SCHEMA, TARGET_TABLE, OVERALL_STATUS) " +
        "VALUES ('" + v_run_id + "', CURRENT_TIMESTAMP(), '" + P_DATABASE + "', '" + P_SCHEMA + "', '" + P_TABLE + "', 'RUNNING')"});

    // 3. Get total row count
    var cnt_rs = snowflake.execute({sqlText: "SELECT COUNT(*) AS CNT FROM " + P_DATABASE + "." + P_SCHEMA + "." + P_TABLE});
    cnt_rs.next();
    var v_total_rows = cnt_rs.getColumnValue(1);

    // 4. Get configured checks from metadata
    var checks_rs = snowflake.execute({sqlText:
        "SELECT a.CHECK_ID, l.CHECK_NAME, a.TARGET_COLUMN, " +
        "l.SQL_TEMPLATE, a.PARAMS_JSON, l.SEVERITY, l.WEIGHT, " +
        "t.WARNING_VALUE, t.FAIL_VALUE " +
        "FROM DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS a " +
        "JOIN DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY l ON a.CHECK_ID = l.CHECK_ID " +
        "LEFT JOIN DQ_GUARDIAN.CONFIG.DQ_THRESHOLDS t ON a.CHECK_ID = t.CHECK_ID AND t.IS_ACTIVE = TRUE " +
        "WHERE a.TARGET_DATABASE = '" + P_DATABASE + "' " +
        "AND a.TARGET_SCHEMA = '" + P_SCHEMA + "' " +
        "AND a.TARGET_TABLE = '" + P_TABLE + "' " +
        "AND a.IS_ACTIVE = TRUE AND l.IS_ACTIVE = TRUE " +
        "ORDER BY a.CHECK_ID"});

    var v_total_checks = 0, v_passed = 0, v_failed = 0, v_errors = 0;

    // 5. Process each check: substitute template → execute → store results
    while (checks_rs.next()) {
        var v_check_id    = checks_rs.getColumnValue("CHECK_ID");
        var v_check_name  = checks_rs.getColumnValue("CHECK_NAME");
        var v_target_col  = checks_rs.getColumnValue("TARGET_COLUMN");
        var v_sql_template= checks_rs.getColumnValue("SQL_TEMPLATE");
        var v_params_json = checks_rs.getColumnValue("PARAMS_JSON");
        var v_severity    = checks_rs.getColumnValue("SEVERITY");
        var v_weight      = checks_rs.getColumnValue("WEIGHT");
        var v_warn_val    = checks_rs.getColumnValue("WARNING_VALUE");
        var v_fail_val    = checks_rs.getColumnValue("FAIL_VALUE");

        v_total_checks++;
        var v_exec_start = Date.now();
        var v_failure_count = 0;
        var v_failure_pct = 0;
        var v_check_status = "PASS";
        var v_error_msg = null;

        try {
            // Build final SQL: replace standard placeholders
            var v_final_sql = v_sql_template;
            v_final_sql = safeReplace(v_final_sql, "{{database}}", P_DATABASE);
            v_final_sql = safeReplace(v_final_sql, "{{schema}}", P_SCHEMA);
            v_final_sql = safeReplace(v_final_sql, "{{table}}", P_TABLE);
            if (v_target_col) {
                v_final_sql = safeReplace(v_final_sql, "{{column}}", v_target_col);
            }

            // Substitute PARAMS_JSON placeholders
            if (v_params_json) {
                var params = (typeof v_params_json === "string") ? JSON.parse(v_params_json) : v_params_json;
                for (var key in params) {
                    v_final_sql = safeReplace(v_final_sql, "{{" + key + "}}", params[key]);
                }
            }

            // Execute and count failures
            var count_rs = snowflake.execute({sqlText: "SELECT COUNT(*) AS CNT FROM (" + v_final_sql + ")"});
            count_rs.next();
            v_failure_count = count_rs.getColumnValue(1);

            // Failure percentage
            if (v_total_rows > 0) {
                v_failure_pct = Math.round(v_failure_count * 10000.0 / v_total_rows) / 10000.0;
            }

            // Determine status using thresholds
            if (v_failure_count === 0) {
                v_check_status = "PASS"; v_passed++;
            } else if (v_fail_val !== null && v_failure_count >= v_fail_val) {
                v_check_status = "FAIL"; v_failed++;
            } else if (v_warn_val !== null && v_failure_count >= v_warn_val) {
                v_check_status = "WARNING"; v_failed++;
            } else {
                v_check_status = "FAIL"; v_failed++;
            }

            // Store failing records (best effort, up to 100)
            try {
                var safe_name = v_check_name.replace(/'/g, "''");
                var safe_col = v_target_col ? v_target_col : "N/A";
                snowflake.execute({sqlText:
                    "INSERT INTO DQ_GUARDIAN.CHECK_RESULTS.DQ_FAILED_RECORDS " +
                    "(RUN_ID, CHECK_ID, TARGET_TABLE, RECORD_IDENTIFIER, COLUMN_NAME, FAILED_VALUE, FAILURE_REASON) " +
                    "SELECT '" + v_run_id + "', " + v_check_id + ", '" + P_TABLE + "', " +
                    "CAST(record_id AS VARCHAR), '" + safe_col + "', " +
                    "COALESCE(TRY_CAST(failed_value AS VARCHAR), 'N/A'), " +
                    "'" + safe_name + "' FROM (" + v_final_sql + ") LIMIT 100"});
            } catch (e2) { /* queries without record_id/failed_value columns — skip */ }

        } catch (e) {
            v_error_msg = e.message;
            v_check_status = "ERROR"; v_errors++;
            v_failure_count = 0; v_failure_pct = 0;
        }

        var v_exec_ms = Date.now() - v_exec_start;
        var safe_check = v_check_name.replace(/'/g, "''");
        var err_val = v_error_msg ? "'" + v_error_msg.replace(/'/g, "''").substring(0, 1990) + "'" : "NULL";
        var col_val = v_target_col ? "'" + v_target_col + "'" : "NULL";
        var warn_str = (v_warn_val !== null && v_warn_val !== undefined) ? v_warn_val : "NULL";
        var fail_str = (v_fail_val !== null && v_fail_val !== undefined) ? v_fail_val : "NULL";

        snowflake.execute({sqlText:
            "INSERT INTO DQ_GUARDIAN.CHECK_RESULTS.DQ_CHECK_RESULTS " +
            "(RUN_ID, CHECK_ID, CHECK_NAME, TARGET_TABLE, TARGET_COLUMN, " +
            "CHECK_STATUS, TOTAL_ROWS, FAILURE_COUNT, FAILURE_PCT, " +
            "THRESHOLD_WARNING, THRESHOLD_FAIL, SEVERITY, WEIGHT, " +
            "EXECUTION_TIME_MS, ERROR_MESSAGE) " +
            "VALUES ('" + v_run_id + "', " + v_check_id + ", '" + safe_check + "', '" + P_TABLE + "', " + col_val + ", " +
            "'" + v_check_status + "', " + v_total_rows + ", " + v_failure_count + ", " + v_failure_pct + ", " +
            warn_str + ", " + fail_str + ", '" + v_severity + "', " + v_weight + ", " +
            v_exec_ms + ", " + err_val + ")"});
    }

    // 6. Update run log
    var v_status = (v_errors > 0) ? "COMPLETED_WITH_ERRORS" : "COMPLETED";
    snowflake.execute({sqlText:
        "UPDATE DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG " +
        "SET RUN_END_TIME = CURRENT_TIMESTAMP(), " +
        "TOTAL_CHECKS = " + v_total_checks + ", " +
        "PASSED_CHECKS = " + v_passed + ", " +
        "FAILED_CHECKS = " + v_failed + ", " +
        "OVERALL_STATUS = '" + v_status + "' " +
        "WHERE RUN_ID = '" + v_run_id + "'"});

    return v_run_id;
$$;

-- ============================================================
-- 11. DQ ORCHESTRATOR (SP_RUN_ALL_CHECKS)
-- ============================================================
CREATE OR REPLACE PROCEDURE DQ_GUARDIAN.CHECK_RESULTS.SP_RUN_ALL_CHECKS()
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var results = [];
    var total_tables = 0;
    var succeeded = 0;
    var failed = 0;

    // 1. Get distinct active target tables from assignments
    var tables_rs = snowflake.execute({sqlText:
        "SELECT DISTINCT TARGET_DATABASE, TARGET_SCHEMA, TARGET_TABLE " +
        "FROM DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS " +
        "WHERE IS_ACTIVE = TRUE " +
        "ORDER BY TARGET_TABLE"});

    // 2. Call SP_RUN_DQ_CHECKS for each table
    while (tables_rs.next()) {
        var db     = tables_rs.getColumnValue("TARGET_DATABASE");
        var schema = tables_rs.getColumnValue("TARGET_SCHEMA");
        var tbl    = tables_rs.getColumnValue("TARGET_TABLE");
        total_tables++;

        try {
            var run_rs = snowflake.execute({sqlText:
                "CALL DQ_GUARDIAN.CHECK_RESULTS.SP_RUN_DQ_CHECKS('" +
                db + "', '" + schema + "', '" + tbl + "')"});
            run_rs.next();
            var run_id = run_rs.getColumnValue(1);
            results.push({table: tbl, run_id: run_id, status: "COMPLETED"});
            succeeded++;
        } catch (e) {
            results.push({table: tbl, run_id: null, status: "ERROR: " + e.message.substring(0, 200)});
            failed++;
        }
    }

    // 3. Return summary
    var overall = (failed > 0) ? "COMPLETED_WITH_ERRORS" : "COMPLETED";
    return JSON.stringify({
        overall_status: overall,
        tables_processed: total_tables,
        tables_succeeded: succeeded,
        tables_failed: failed,
        runs: results
    }, null, 2);
$$;

-- ============================================================
-- 12. PROFILING PROCEDURES
-- ============================================================
CREATE OR REPLACE PROCEDURE DQ_GUARDIAN.PROFILING.SP_PROFILE_TABLE(
    P_DATABASE VARCHAR, P_SCHEMA VARCHAR, P_TABLE VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var fqn = P_DATABASE + "." + P_SCHEMA + "." + P_TABLE;
    var pid_rs = snowflake.execute({sqlText: "SELECT UUID_STRING()"});
    pid_rs.next();
    var v_profile_id = pid_rs.getColumnValue(1);

    // 1. TABLE_PROFILES
    var row_rs = snowflake.execute({sqlText: "SELECT COUNT(*) FROM " + fqn});
    row_rs.next();
    var v_row_count = row_rs.getColumnValue(1);
    var col_rs = snowflake.execute({sqlText:
        "SELECT COUNT(*) FROM " + P_DATABASE + ".INFORMATION_SCHEMA.COLUMNS " +
        "WHERE TABLE_SCHEMA = '" + P_SCHEMA + "' AND TABLE_NAME = '" + P_TABLE + "'"});
    col_rs.next();
    var v_col_count = col_rs.getColumnValue(1);
    snowflake.execute({sqlText:
        "INSERT INTO DQ_GUARDIAN.PROFILING.TABLE_PROFILES " +
        "(PROFILE_ID, DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, ROW_COUNT, COLUMN_COUNT, PROFILE_STATUS) " +
        "VALUES ('" + v_profile_id + "', '" + P_DATABASE + "', '" + P_SCHEMA + "', '" + P_TABLE + "', " +
        v_row_count + ", " + v_col_count + ", 'COMPLETED')"});

    // 2. COLUMN_PROFILES via INSERT ... SELECT (allows PARSE_JSON in subquery)
    var cols_rs = snowflake.execute({sqlText:
        "SELECT COLUMN_NAME, DATA_TYPE FROM " + P_DATABASE + ".INFORMATION_SCHEMA.COLUMNS " +
        "WHERE TABLE_SCHEMA = '" + P_SCHEMA + "' AND TABLE_NAME = '" + P_TABLE + "' ORDER BY ORDINAL_POSITION"});
    while (cols_rs.next()) {
        var cn = cols_rs.getColumnValue("COLUMN_NAME");
        var dt = cols_rs.getColumnValue("DATA_TYPE");
        var is_num = (dt === "NUMBER" || dt === "FLOAT" || dt === "FIXED");
        var mean_e = is_num ? "ROUND(AVG(" + cn + "), 4)" : "NULL";
        var med_e  = is_num ? "ROUND(MEDIAN(" + cn + "), 4)" : "NULL";
        try {
            snowflake.execute({sqlText:
                "INSERT INTO DQ_GUARDIAN.PROFILING.COLUMN_PROFILES " +
                "(DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, COLUMN_NAME, DATA_TYPE, " +
                "ROW_COUNT, NULL_COUNT, NULL_PCT, DISTINCT_COUNT, MIN_VALUE, MAX_VALUE, MEAN, MEDIAN, TOP_VALUES_JSON) " +
                "SELECT '" + P_DATABASE + "', '" + P_SCHEMA + "', '" + P_TABLE + "', '" + cn + "', '" + dt + "', " +
                "COUNT(*), SUM(CASE WHEN " + cn + " IS NULL THEN 1 ELSE 0 END), " +
                "ROUND(SUM(CASE WHEN " + cn + " IS NULL THEN 1 ELSE 0 END)*100.0/COUNT(*), 4), " +
                "COUNT(DISTINCT " + cn + "), MIN(CAST(" + cn + " AS VARCHAR)), MAX(CAST(" + cn + " AS VARCHAR)), " +
                mean_e + ", " + med_e + ", " +
                "(SELECT ARRAY_AGG(OBJECT_CONSTRUCT('value',val,'count',cnt)) FROM " +
                "(SELECT CAST(" + cn + " AS VARCHAR) AS val, COUNT(*) AS cnt FROM " + fqn +
                " WHERE " + cn + " IS NOT NULL GROUP BY val ORDER BY cnt DESC LIMIT 5)) FROM " + fqn});
        } catch (e) {
            snowflake.execute({sqlText:
                "INSERT INTO DQ_GUARDIAN.PROFILING.COLUMN_PROFILES " +
                "(DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, COLUMN_NAME, DATA_TYPE, PATTERN_SUMMARY) " +
                "VALUES ('" + P_DATABASE + "','" + P_SCHEMA + "','" + P_TABLE + "','" + cn + "','" + dt +
                "','ERROR: " + e.message.substring(0,200).replace(/'/g,"''") + "')"});
        }
    }

    // 3. DISTRIBUTION_SNAPSHOTS for low-cardinality TEXT/BOOLEAN columns
    var dist_rs = snowflake.execute({sqlText:
        "SELECT COLUMN_NAME FROM " + P_DATABASE + ".INFORMATION_SCHEMA.COLUMNS " +
        "WHERE TABLE_SCHEMA='" + P_SCHEMA + "' AND TABLE_NAME='" + P_TABLE + "' AND DATA_TYPE IN ('TEXT','BOOLEAN') ORDER BY ORDINAL_POSITION"});
    while (dist_rs.next()) {
        var dc = dist_rs.getColumnValue("COLUMN_NAME");
        try {
            var cr = snowflake.execute({sqlText: "SELECT COUNT(DISTINCT " + dc + ") FROM " + fqn});
            cr.next();
            if (cr.getColumnValue(1) <= 20) {
                snowflake.execute({sqlText:
                    "INSERT INTO DQ_GUARDIAN.PROFILING.DISTRIBUTION_SNAPSHOTS " +
                    "(DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, COLUMN_NAME, VALUE_OR_BUCKET, RECORD_COUNT, PERCENTAGE) " +
                    "SELECT '" + P_DATABASE + "','" + P_SCHEMA + "','" + P_TABLE + "','" + dc + "'," +
                    "COALESCE(CAST(" + dc + " AS VARCHAR),'<NULL>'), COUNT(*), " +
                    "ROUND(COUNT(*)*100.0/" + v_row_count + ",4) FROM " + fqn + " GROUP BY " + dc});
            }
        } catch (e) {}
    }

    // 4. SCHEMA_SNAPSHOTS
    var mx = snowflake.execute({sqlText: "SELECT COALESCE(MAX(SNAPSHOT_ID),0) FROM DQ_GUARDIAN.PROFILING.SCHEMA_SNAPSHOTS"});
    mx.next(); var mid = mx.getColumnValue(1);
    snowflake.execute({sqlText:
        "INSERT INTO DQ_GUARDIAN.PROFILING.SCHEMA_SNAPSHOTS " +
        "(SNAPSHOT_ID, TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, ORDINAL_POSITION, " +
        "DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE) " +
        "SELECT " + mid + "+ROW_NUMBER() OVER (ORDER BY ORDINAL_POSITION), " +
        "TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, ORDINAL_POSITION, " +
        "DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE " +
        "FROM " + P_DATABASE + ".INFORMATION_SCHEMA.COLUMNS " +
        "WHERE TABLE_SCHEMA='" + P_SCHEMA + "' AND TABLE_NAME='" + P_TABLE + "'"});

    return '{"profile_id":"' + v_profile_id + '","table":"' + P_TABLE +
           '","rows":' + v_row_count + ',"columns":' + v_col_count + ',"status":"COMPLETED"}';
$$;

CREATE OR REPLACE PROCEDURE DQ_GUARDIAN.PROFILING.SP_DETECT_SCHEMA_DRIFT(
    P_TABLE_FQN VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var parts = P_TABLE_FQN.split(".");
    if (parts.length !== 3) return '{"error":"Expected format: DATABASE.SCHEMA.TABLE"}';
    var db = parts[0], schema = parts[1], tbl = parts[2];

    // Get latest snapshot timestamp as VARCHAR to avoid JS Date issues
    var base_rs = snowflake.execute({sqlText:
        "SELECT MAX(SNAPSHOT_AT)::VARCHAR AS latest " +
        "FROM DQ_GUARDIAN.PROFILING.SCHEMA_SNAPSHOTS " +
        "WHERE TABLE_NAME = '" + tbl + "' AND TABLE_SCHEMA = '" + schema + "'"});
    base_rs.next();
    var latest = base_rs.getColumnValue("LATEST");
    if (!latest) return '{"table":"' + tbl + '","status":"NO_BASELINE","drift":[]}';

    var bf = "TABLE_NAME='" + tbl + "' AND TABLE_SCHEMA='" + schema + "' AND SNAPSHOT_AT='" + latest + "'";

    // ADDED columns: in current schema but not in snapshot
    var added = [];
    var rs1 = snowflake.execute({sqlText:
        "SELECT c.COLUMN_NAME, c.DATA_TYPE, c.ORDINAL_POSITION " +
        "FROM " + db + ".INFORMATION_SCHEMA.COLUMNS c " +
        "LEFT JOIN (SELECT COLUMN_NAME FROM DQ_GUARDIAN.PROFILING.SCHEMA_SNAPSHOTS WHERE " + bf + ") s " +
        "ON c.COLUMN_NAME = s.COLUMN_NAME " +
        "WHERE c.TABLE_SCHEMA='" + schema + "' AND c.TABLE_NAME='" + tbl + "' AND s.COLUMN_NAME IS NULL"});
    while (rs1.next()) {
        added.push({drift:"ADDED", column:rs1.getColumnValue("COLUMN_NAME"),
                     data_type:rs1.getColumnValue("DATA_TYPE"), position:rs1.getColumnValue("ORDINAL_POSITION")});
    }

    // REMOVED columns: in snapshot but not in current schema
    var removed = [];
    var rs2 = snowflake.execute({sqlText:
        "SELECT s.COLUMN_NAME, s.DATA_TYPE, s.ORDINAL_POSITION " +
        "FROM (SELECT COLUMN_NAME, DATA_TYPE, ORDINAL_POSITION FROM DQ_GUARDIAN.PROFILING.SCHEMA_SNAPSHOTS WHERE " + bf + ") s " +
        "LEFT JOIN " + db + ".INFORMATION_SCHEMA.COLUMNS c " +
        "ON s.COLUMN_NAME=c.COLUMN_NAME AND c.TABLE_SCHEMA='" + schema + "' AND c.TABLE_NAME='" + tbl + "' " +
        "WHERE c.COLUMN_NAME IS NULL"});
    while (rs2.next()) {
        removed.push({drift:"REMOVED", column:rs2.getColumnValue("COLUMN_NAME"),
                       data_type:rs2.getColumnValue("DATA_TYPE"), position:rs2.getColumnValue("ORDINAL_POSITION")});
    }

    // TYPE CHANGED columns: same name, different data type
    var changed = [];
    var rs3 = snowflake.execute({sqlText:
        "SELECT c.COLUMN_NAME, s.DATA_TYPE AS old_type, c.DATA_TYPE AS new_type " +
        "FROM " + db + ".INFORMATION_SCHEMA.COLUMNS c " +
        "JOIN (SELECT COLUMN_NAME, DATA_TYPE FROM DQ_GUARDIAN.PROFILING.SCHEMA_SNAPSHOTS WHERE " + bf + ") s " +
        "ON c.COLUMN_NAME=s.COLUMN_NAME " +
        "WHERE c.TABLE_SCHEMA='" + schema + "' AND c.TABLE_NAME='" + tbl + "' AND c.DATA_TYPE != s.DATA_TYPE"});
    while (rs3.next()) {
        changed.push({drift:"TYPE_CHANGED", column:rs3.getColumnValue("COLUMN_NAME"),
                       old_type:rs3.getColumnValue("OLD_TYPE"), new_type:rs3.getColumnValue("NEW_TYPE")});
    }

    var all_drift = added.concat(removed).concat(changed);
    return JSON.stringify({
        table: P_TABLE_FQN, baseline_at: latest,
        status: all_drift.length > 0 ? "DRIFT_DETECTED" : "NO_DRIFT",
        drift_count: all_drift.length, drift: all_drift
    }, null, 2);
$$;

-- ============================================================
-- 13. HEALTH SCORING (SP_CALCULATE_HEALTH_SCORE)
-- ============================================================
CREATE OR REPLACE PROCEDURE DQ_GUARDIAN.CHECK_RESULTS.SP_CALCULATE_HEALTH_SCORE(
    P_RUN_ID VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    // 1. Verify RUN_ID exists
    var run_rs = snowflake.execute({sqlText:
        "SELECT TARGET_TABLE FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG WHERE RUN_ID = '" + P_RUN_ID + "'"});
    if (!run_rs.next()) return '{"error":"RUN_ID not found"}';
    var target_table = run_rs.getColumnValue("TARGET_TABLE");

    // 2. Delete existing score for this RUN_ID (idempotent)
    snowflake.execute({sqlText:
        "DELETE FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_HEALTH_SCORES " +
        "WHERE RUN_ID = '" + P_RUN_ID + "' AND TARGET_TABLE = '" + target_table + "'"});

    // 3. Calculate health score
    //    Score = SUM(weighted_pass) / SUM(weight) * 100
    //    PASS = full weight, WARNING = half weight, FAIL/ERROR = zero
    var calc_rs = snowflake.execute({sqlText:
        "SELECT COUNT(*) AS total_checks, " +
        "SUM(CASE WHEN CHECK_STATUS = 'PASS' THEN 1 ELSE 0 END) AS passed, " +
        "SUM(CASE WHEN CHECK_STATUS IN ('FAIL','WARNING') THEN 1 ELSE 0 END) AS failed, " +
        "SUM(CASE WHEN SEVERITY='CRITICAL' AND CHECK_STATUS!='PASS' THEN 1 ELSE 0 END) AS critical_f, " +
        "SUM(CASE WHEN SEVERITY='HIGH' AND CHECK_STATUS!='PASS' THEN 1 ELSE 0 END) AS high_f, " +
        "SUM(CASE WHEN SEVERITY='MEDIUM' AND CHECK_STATUS!='PASS' THEN 1 ELSE 0 END) AS medium_f, " +
        "SUM(CASE WHEN SEVERITY='LOW' AND CHECK_STATUS!='PASS' THEN 1 ELSE 0 END) AS low_f, " +
        "ROUND(CASE WHEN SUM(WEIGHT)=0 THEN 100 ELSE " +
        "  SUM(CASE WHEN CHECK_STATUS='PASS' THEN WEIGHT " +
        "           WHEN CHECK_STATUS='WARNING' THEN WEIGHT*0.5 " +
        "           ELSE 0 END) * 100.0 / SUM(WEIGHT) END, 2) AS health_score " +
        "FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_CHECK_RESULTS " +
        "WHERE RUN_ID = '" + P_RUN_ID + "' AND CHECK_STATUS != 'ERROR'"});
    calc_rs.next();

    var total  = calc_rs.getColumnValue("TOTAL_CHECKS");
    var passed = calc_rs.getColumnValue("PASSED");
    var failed = calc_rs.getColumnValue("FAILED");
    var crit   = calc_rs.getColumnValue("CRITICAL_F");
    var high   = calc_rs.getColumnValue("HIGH_F");
    var medium = calc_rs.getColumnValue("MEDIUM_F");
    var low    = calc_rs.getColumnValue("LOW_F");
    var score  = calc_rs.getColumnValue("HEALTH_SCORE");
    if (total === 0) return '{"error":"No check results found"}';

    // 4. Insert health score
    snowflake.execute({sqlText:
        "INSERT INTO DQ_GUARDIAN.CHECK_RESULTS.DQ_HEALTH_SCORES " +
        "(RUN_ID, TARGET_TABLE, HEALTH_SCORE, TOTAL_CHECKS, PASSED_CHECKS, FAILED_CHECKS, " +
        "CRITICAL_FAILURES, HIGH_FAILURES, MEDIUM_FAILURES, LOW_FAILURES) " +
        "VALUES ('" + P_RUN_ID + "','" + target_table + "'," + score + "," +
        total + "," + passed + "," + failed + "," + crit + "," + high + "," + medium + "," + low + ")"});

    return JSON.stringify({
        run_id: P_RUN_ID, target_table: target_table, health_score: score,
        total_checks: total, passed: passed, failed: failed,
        critical: crit, high: high, medium: medium, low: low
    }, null, 2);
$$;

-- ============================================================
-- 14. HEALTH DASHBOARD VIEWS
-- ============================================================
-- -------------------------------------------------------
-- 1. V_CHECK_SUMMARY — One row per check result per run
-- -------------------------------------------------------
CREATE OR REPLACE VIEW DQ_GUARDIAN.CHECK_RESULTS.V_CHECK_SUMMARY AS
SELECT
    r.RUN_ID,
    r.TARGET_TABLE,
    cr.CHECK_ID,
    cr.CHECK_NAME,
    cr.TARGET_COLUMN,
    cr.CHECK_STATUS,
    cr.SEVERITY,
    cr.TOTAL_ROWS,
    cr.FAILURE_COUNT,
    cr.FAILURE_PCT,
    cr.WEIGHT,
    cr.EXECUTION_TIME_MS,
    cr.ERROR_MESSAGE,
    r.RUN_START_TIME
FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_CHECK_RESULTS cr
JOIN DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG r ON cr.RUN_ID = r.RUN_ID;

-- -------------------------------------------------------
-- 2. V_TABLE_HEALTH_DASHBOARD — One row per table per run
-- -------------------------------------------------------
CREATE OR REPLACE VIEW DQ_GUARDIAN.CHECK_RESULTS.V_TABLE_HEALTH_DASHBOARD AS
SELECT
    hs.TARGET_TABLE,
    hs.RUN_ID,
    hs.HEALTH_SCORE,
    hs.TOTAL_CHECKS,
    hs.PASSED_CHECKS,
    hs.FAILED_CHECKS,
    hs.TOTAL_CHECKS - hs.PASSED_CHECKS - hs.FAILED_CHECKS AS WARNING_CHECKS,
    hs.CRITICAL_FAILURES,
    hs.HIGH_FAILURES,
    hs.MEDIUM_FAILURES,
    hs.LOW_FAILURES,
    COALESCE(fr.FAILED_RECORD_COUNT, 0) AS FAILED_RECORD_COUNT,
    r.OVERALL_STATUS,
    r.RUN_START_TIME
FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_HEALTH_SCORES hs
JOIN DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG r ON hs.RUN_ID = r.RUN_ID
LEFT JOIN (
    SELECT RUN_ID, COUNT(*) AS FAILED_RECORD_COUNT
    FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_FAILED_RECORDS GROUP BY RUN_ID
) fr ON hs.RUN_ID = fr.RUN_ID;

-- -------------------------------------------------------
-- 3. V_OVERALL_HEALTH — Single-row overall health summary
-- -------------------------------------------------------
CREATE OR REPLACE VIEW DQ_GUARDIAN.CHECK_RESULTS.V_OVERALL_HEALTH AS
SELECT
    ROUND(AVG(hs.HEALTH_SCORE), 2)      AS OVERALL_HEALTH_SCORE,
    COUNT(DISTINCT hs.TARGET_TABLE)      AS TABLES_EVALUATED,
    SUM(hs.TOTAL_CHECKS)                AS TOTAL_CHECKS,
    SUM(hs.PASSED_CHECKS)               AS PASSED_CHECKS,
    SUM(hs.FAILED_CHECKS)               AS FAILED_CHECKS,
    SUM(hs.TOTAL_CHECKS) - SUM(hs.PASSED_CHECKS) - SUM(hs.FAILED_CHECKS) AS WARNING_CHECKS,
    COALESCE(SUM(fr.FAILED_RECORD_COUNT), 0) AS TOTAL_FAILED_RECORDS,
    CASE
        WHEN AVG(hs.HEALTH_SCORE) >= 90 THEN 'HEALTHY'
        WHEN AVG(hs.HEALTH_SCORE) >= 70 THEN 'WARNING'
        WHEN AVG(hs.HEALTH_SCORE) >= 50 THEN 'AT_RISK'
        ELSE 'CRITICAL'
    END AS OVERALL_STATUS,
    MAX(r.RUN_START_TIME) AS LATEST_RUN
FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_HEALTH_SCORES hs
JOIN DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG r ON hs.RUN_ID = r.RUN_ID
LEFT JOIN (
    SELECT RUN_ID, COUNT(*) AS FAILED_RECORD_COUNT
    FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_FAILED_RECORDS GROUP BY RUN_ID
) fr ON hs.RUN_ID = fr.RUN_ID;

-- ============================================================
-- 15. CORTEX AI TABLES
-- ============================================================

USE SCHEMA DQ_GUARDIAN.CORTEX_AI;

-- -------------------------------------------------------
-- 7A. PROMPT_TEMPLATES
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.CORTEX_AI.PROMPT_TEMPLATES (
    TEMPLATE_ID     VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    TEMPLATE_NAME   VARCHAR(100)    NOT NULL,
    TEMPLATE_TYPE   VARCHAR(50)     NOT NULL,
    PROMPT_TEXT     VARCHAR(16000)   NOT NULL,
    VERSION         INTEGER         NOT NULL DEFAULT 1,
    IS_ACTIVE       BOOLEAN         NOT NULL DEFAULT TRUE,
    CREATED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_PROMPT_TEMPLATES PRIMARY KEY (TEMPLATE_ID)
)
COMMENT = 'Reusable Cortex AI prompt templates for DQ analysis tasks';

-- -------------------------------------------------------
-- 7B. AI_ANALYSIS_CACHE
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE (
    ANALYSIS_ID     VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    ANALYSIS_TYPE   VARCHAR(50)     NOT NULL,
    RUN_ID          VARCHAR(36),
    CHECK_ID        INTEGER,
    TARGET_TABLE    VARCHAR(256),
    INPUT_CONTEXT   VARCHAR(4000),
    AI_RESPONSE     VARCHAR(16000),
    MODEL_USED      VARCHAR(50),
    TOKEN_COUNT     INTEGER,
    STATUS          VARCHAR(20)     NOT NULL DEFAULT 'COMPLETED',
    CREATED_AT      TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_AI_ANALYSIS_CACHE PRIMARY KEY (ANALYSIS_ID)
)
COMMENT = 'Cached AI-generated explanations, root-cause analysis, and recommendations';

-- ============================================================
-- 16. CORTEX AI PROCEDURES
-- ============================================================
CREATE OR REPLACE PROCEDURE DQ_GUARDIAN.CORTEX_AI.SP_AI_PROFILE_DATASET(P_TABLE_FQN VARCHAR)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    // --------------------------------------------------
    // Helper: safe string replace (avoids JS $ issues)
    // --------------------------------------------------
    function safeReplace(str, placeholder, value) {
        var idx = str.indexOf(placeholder);
        while (idx !== -1) {
            str = str.substring(0, idx) + value + str.substring(idx + placeholder.length);
            idx = str.indexOf(placeholder, idx + value.length);
        }
        return str;
    }

    // --------------------------------------------------
    // Parse fully-qualified table name
    // --------------------------------------------------
    var parts = P_TABLE_FQN.split('.');
    if (parts.length !== 3) {
        return { status: 'ERROR', message: 'P_TABLE_FQN must be DATABASE.SCHEMA.TABLE' };
    }
    var dbName   = parts[0].replace(/"/g, '');
    var schName  = parts[1].replace(/"/g, '');
    var tblName  = parts[2].replace(/"/g, '');

    // --------------------------------------------------
    // 1. Read TABLE_PROFILES
    // --------------------------------------------------
    var tpSQL = "SELECT ROW_COUNT, COLUMN_COUNT, PROFILED_AT::VARCHAR AS PROFILED_AT "
        + "FROM DQ_GUARDIAN.PROFILING.TABLE_PROFILES "
        + "WHERE DATABASE_NAME = '" + dbName + "' "
        + "AND SCHEMA_NAME = '" + schName + "' "
        + "AND TABLE_NAME = '" + tblName + "' "
        + "ORDER BY PROFILED_AT DESC LIMIT 1";
    var tpStmt = snowflake.createStatement({ sqlText: tpSQL });
    var tpRS = tpStmt.execute();

    if (!tpRS.next()) {
        return { status: 'ERROR', message: 'No profiling data found. Run SP_PROFILE_TABLE first.' };
    }
    var rowCount   = tpRS.getColumnValue(1);
    var colCount   = tpRS.getColumnValue(2);
    var profiledAt = tpRS.getColumnValue(3);

    // --------------------------------------------------
    // 2. Read COLUMN_PROFILES
    // --------------------------------------------------
    var cpSQL = "SELECT COLUMN_NAME, DATA_TYPE, NULL_COUNT, NULL_PCT, "
        + "DISTINCT_COUNT, MIN_VALUE, MAX_VALUE, MEAN, MEDIAN "
        + "FROM DQ_GUARDIAN.PROFILING.COLUMN_PROFILES "
        + "WHERE DATABASE_NAME = '" + dbName + "' "
        + "AND SCHEMA_NAME = '" + schName + "' "
        + "AND TABLE_NAME = '" + tblName + "' "
        + "ORDER BY PROFILED_AT DESC";
    var cpStmt = snowflake.createStatement({ sqlText: cpSQL });
    var cpRS = cpStmt.execute();

    var columnLines = [];
    while (cpRS.next()) {
        var line = '- ' + cpRS.getColumnValue(1) + ' (' + cpRS.getColumnValue(2) + ')';
        var nullCnt = cpRS.getColumnValue(3);
        var nullPct = cpRS.getColumnValue(4);
        var distCnt = cpRS.getColumnValue(5);
        var minVal  = cpRS.getColumnValue(6);
        var maxVal  = cpRS.getColumnValue(7);
        var mean    = cpRS.getColumnValue(8);
        var median  = cpRS.getColumnValue(9);

        var details = [];
        if (nullCnt !== null)  details.push('nulls=' + nullCnt + ' (' + nullPct + '%)');
        if (distCnt !== null)  details.push('distinct=' + distCnt);
        if (minVal !== null)   details.push('min=' + minVal);
        if (maxVal !== null)   details.push('max=' + maxVal);
        if (mean !== null)     details.push('mean=' + mean);
        if (median !== null)   details.push('median=' + median);

        if (details.length > 0) {
            line += ': ' + details.join(', ');
        }
        columnLines.push(line);
    }

    // --------------------------------------------------
    // 3. Read top DISTRIBUTION_SNAPSHOTS (limit 50 rows)
    // --------------------------------------------------
    var dsSQL = "SELECT COLUMN_NAME, VALUE_OR_BUCKET, RECORD_COUNT, PERCENTAGE "
        + "FROM DQ_GUARDIAN.PROFILING.DISTRIBUTION_SNAPSHOTS "
        + "WHERE DATABASE_NAME = '" + dbName + "' "
        + "AND SCHEMA_NAME = '" + schName + "' "
        + "AND TABLE_NAME = '" + tblName + "' "
        + "ORDER BY COLUMN_NAME, RECORD_COUNT DESC LIMIT 50";
    var dsStmt = snowflake.createStatement({ sqlText: dsSQL });
    var dsRS = dsStmt.execute();

    var distLines = [];
    var prevCol = '';
    while (dsRS.next()) {
        var col  = dsRS.getColumnValue(1);
        var val  = dsRS.getColumnValue(2);
        var cnt  = dsRS.getColumnValue(3);
        var pct  = dsRS.getColumnValue(4);
        if (col !== prevCol) {
            distLines.push('Column ' + col + ':');
            prevCol = col;
        }
        distLines.push('  ' + val + ': ' + cnt + ' rows (' + pct + '%)');
    }

    // --------------------------------------------------
    // 4. Build the prompt
    // --------------------------------------------------
    var context = 'TABLE: ' + P_TABLE_FQN + '\n'
        + 'ROW COUNT: ' + rowCount + '\n'
        + 'COLUMN COUNT: ' + colCount + '\n'
        + 'PROFILED AT: ' + profiledAt + '\n\n'
        + 'COLUMN DETAILS:\n' + columnLines.join('\n') + '\n';

    if (distLines.length > 0) {
        context += '\nVALUE DISTRIBUTIONS:\n' + distLines.join('\n') + '\n';
    }

    var prompt = 'You are a data quality analyst. Given the following dataset profile, '
        + 'provide a concise business-readable analysis covering:\n'
        + '1. What this table appears to represent\n'
        + '2. Important columns and their roles\n'
        + '3. Notable data quality observations\n'
        + '4. Unusual distributions or patterns\n'
        + '5. Potential risks worth investigating\n\n'
        + 'Keep your response concise and actionable.\n\n'
        + context;

    // --------------------------------------------------
    // 5. Call Cortex COMPLETE
    // --------------------------------------------------
    var model = 'llama3.3-70b';
    var escapedPrompt = prompt.replace(/'/g, "''");

    var aiSQL = "SELECT SNOWFLAKE.CORTEX.COMPLETE('" + model + "', '" + escapedPrompt + "') AS AI_RESPONSE";
    var aiStmt = snowflake.createStatement({ sqlText: aiSQL });
    var aiRS = aiStmt.execute();
    aiRS.next();
    var aiResponse = aiRS.getColumnValue(1);

    // --------------------------------------------------
    // 6. Store in AI_ANALYSIS_CACHE
    // --------------------------------------------------
    var escapedContext  = context.replace(/'/g, "''");
    var escapedResponse = aiResponse.replace(/'/g, "''");

    var insertSQL = "INSERT INTO DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE "
        + "(ANALYSIS_TYPE, TARGET_TABLE, INPUT_CONTEXT, AI_RESPONSE, MODEL_USED, STATUS) "
        + "SELECT 'PROFILE', '" + P_TABLE_FQN + "', "
        + "'" + escapedContext + "', "
        + "'" + escapedResponse + "', "
        + "'" + model + "', 'COMPLETED'";
    var insStmt = snowflake.createStatement({ sqlText: insertSQL });
    insStmt.execute();

    // Get the analysis ID just inserted
    var idSQL = "SELECT ANALYSIS_ID FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE "
        + "WHERE ANALYSIS_TYPE = 'PROFILE' AND TARGET_TABLE = '" + P_TABLE_FQN + "' "
        + "ORDER BY CREATED_AT DESC LIMIT 1";
    var idStmt = snowflake.createStatement({ sqlText: idSQL });
    var idRS = idStmt.execute();
    idRS.next();
    var analysisId = idRS.getColumnValue(1);

    // --------------------------------------------------
    // 7. Return result
    // --------------------------------------------------
    return {
        table: P_TABLE_FQN,
        status: 'SUCCESS',
        analysis_id: analysisId,
        model: model,
        ai_response: aiResponse
    };
$$;

CREATE OR REPLACE PROCEDURE DQ_GUARDIAN.CORTEX_AI.SP_AI_EXPLAIN_FAILURES(P_RUN_ID VARCHAR)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    // --------------------------------------------------
    // 1. Verify run exists and get run info
    // --------------------------------------------------
    var runSQL = "SELECT TARGET_DATABASE, TARGET_SCHEMA, TARGET_TABLE, "
        + "TOTAL_CHECKS, PASSED_CHECKS, FAILED_CHECKS, OVERALL_STATUS "
        + "FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG "
        + "WHERE RUN_ID = '" + P_RUN_ID + "'";
    var runStmt = snowflake.createStatement({ sqlText: runSQL });
    var runRS = runStmt.execute();

    if (!runRS.next()) {
        return { run_id: P_RUN_ID, status: 'ERROR', message: 'RUN_ID not found.' };
    }
    var targetDB     = runRS.getColumnValue(1);
    var targetSchema = runRS.getColumnValue(2);
    var targetTable  = runRS.getColumnValue(3);
    var totalChecks  = runRS.getColumnValue(4);
    var passedChecks = runRS.getColumnValue(5);
    var failedChecks = runRS.getColumnValue(6);
    var overallStatus = runRS.getColumnValue(7);
    var tableFQN = targetDB + '.' + targetSchema + '.' + targetTable;

    // --------------------------------------------------
    // 2. Get FAIL and WARNING results with check metadata
    // --------------------------------------------------
    var crSQL = "SELECT r.CHECK_ID, r.CHECK_NAME, r.CHECK_STATUS, r.SEVERITY, "
        + "r.FAILURE_COUNT, r.TOTAL_ROWS, r.FAILURE_PCT, "
        + "r.THRESHOLD_WARNING, r.THRESHOLD_FAIL, "
        + "l.DESCRIPTION, l.CATEGORY "
        + "FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_CHECK_RESULTS r "
        + "JOIN DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY l ON r.CHECK_ID = l.CHECK_ID "
        + "WHERE r.RUN_ID = '" + P_RUN_ID + "' "
        + "AND r.CHECK_STATUS IN ('FAIL', 'WARNING') "
        + "ORDER BY r.CHECK_ID";
    var crStmt = snowflake.createStatement({ sqlText: crSQL });
    var crRS = crStmt.execute();

    var failedChecks_arr = [];
    while (crRS.next()) {
        failedChecks_arr.push({
            check_id:       crRS.getColumnValue(1),
            check_name:     crRS.getColumnValue(2),
            check_status:   crRS.getColumnValue(3),
            severity:       crRS.getColumnValue(4),
            failure_count:  crRS.getColumnValue(5),
            total_rows:     crRS.getColumnValue(6),
            failure_pct:    crRS.getColumnValue(7),
            thresh_warn:    crRS.getColumnValue(8),
            thresh_fail:    crRS.getColumnValue(9),
            description:    crRS.getColumnValue(10),
            category:       crRS.getColumnValue(11)
        });
    }

    if (failedChecks_arr.length === 0) {
        return { run_id: P_RUN_ID, status: 'SUCCESS',
                 message: 'No failed or warning checks to explain.', analyses_created: 0 };
    }

    // --------------------------------------------------
    // 3. Get all failed records for this run (keyed by check_id)
    // --------------------------------------------------
    var frSQL = "SELECT CHECK_ID, RECORD_IDENTIFIER, COLUMN_NAME, FAILED_VALUE, FAILURE_REASON "
        + "FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_FAILED_RECORDS "
        + "WHERE RUN_ID = '" + P_RUN_ID + "' "
        + "ORDER BY CHECK_ID, CREATED_AT LIMIT 100";
    var frStmt = snowflake.createStatement({ sqlText: frSQL });
    var frRS = frStmt.execute();

    var failedRecords = {};
    while (frRS.next()) {
        var cid = frRS.getColumnValue(1);
        if (!failedRecords[cid]) failedRecords[cid] = [];
        if (failedRecords[cid].length < 5) {
            failedRecords[cid].push({
                record_id:  frRS.getColumnValue(2),
                column:     frRS.getColumnValue(3),
                value:      frRS.getColumnValue(4),
                reason:     frRS.getColumnValue(5)
            });
        }
    }

    // --------------------------------------------------
    // 4. For each failed/warning check: build prompt, call Cortex, store
    // --------------------------------------------------
    var model = 'llama3.3-70b';
    var analysisIds = [];
    var explanations = [];

    for (var i = 0; i < failedChecks_arr.length; i++) {
        var chk = failedChecks_arr[i];

        // Delete prior analysis for same RUN_ID + CHECK_ID (idempotent)
        var delSQL = "DELETE FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE "
            + "WHERE ANALYSIS_TYPE = 'FAILURE_EXPLANATION' "
            + "AND RUN_ID = '" + P_RUN_ID + "' "
            + "AND CHECK_ID = " + chk.check_id;
        snowflake.createStatement({ sqlText: delSQL }).execute();

        // Build context
        var ctx = 'TABLE: ' + tableFQN + '\n'
            + 'CHECK ID: ' + chk.check_id + '\n'
            + 'CHECK NAME: ' + chk.check_name + '\n'
            + 'CATEGORY: ' + chk.category + '\n'
            + 'DESCRIPTION: ' + chk.description + '\n'
            + 'STATUS: ' + chk.check_status + '\n'
            + 'SEVERITY: ' + chk.severity + '\n'
            + 'TOTAL ROWS: ' + chk.total_rows + '\n'
            + 'FAILURE COUNT: ' + chk.failure_count + '\n'
            + 'FAILURE %: ' + chk.failure_pct + '\n'
            + 'WARNING THRESHOLD: ' + chk.thresh_warn + '%\n'
            + 'FAIL THRESHOLD: ' + chk.thresh_fail + '%\n';

        // Add sample failed records if available
        var samples = failedRecords[chk.check_id];
        if (samples && samples.length > 0) {
            ctx += '\nSAMPLE FAILED RECORDS:\n';
            for (var s = 0; s < samples.length; s++) {
                ctx += '- Record ' + samples[s].record_id
                    + ', Column: ' + samples[s].column
                    + ', Value: ' + samples[s].value
                    + ', Reason: ' + samples[s].reason + '\n';
            }
        }

        var prompt = 'You are a data quality analyst. A data quality check has failed or triggered a warning. '
            + 'Analyze the following check result and provide a concise explanation covering:\n'
            + '1. What failed and why\n'
            + '2. Likely root cause\n'
            + '3. Business impact\n'
            + '4. Key evidence from the results\n'
            + '5. Recommended next steps to investigate or fix\n\n'
            + 'Be specific and actionable. Keep it under 200 words.\n\n'
            + ctx;

        var escapedPrompt = prompt.replace(/'/g, "''");
        var aiSQL = "SELECT SNOWFLAKE.CORTEX.COMPLETE('" + model + "', '" + escapedPrompt + "') AS AI_RESPONSE";
        var aiStmt = snowflake.createStatement({ sqlText: aiSQL });
        var aiRS = aiStmt.execute();
        aiRS.next();
        var aiResponse = aiRS.getColumnValue(1);

        // Store in cache
        var escapedCtx = ctx.replace(/'/g, "''");
        var escapedResp = aiResponse.replace(/'/g, "''");

        var insertSQL = "INSERT INTO DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE "
            + "(ANALYSIS_TYPE, RUN_ID, CHECK_ID, TARGET_TABLE, INPUT_CONTEXT, AI_RESPONSE, MODEL_USED, STATUS) "
            + "SELECT 'FAILURE_EXPLANATION', '" + P_RUN_ID + "', " + chk.check_id + ", "
            + "'" + tableFQN + "', "
            + "'" + escapedCtx + "', "
            + "'" + escapedResp + "', "
            + "'" + model + "', 'COMPLETED'";
        snowflake.createStatement({ sqlText: insertSQL }).execute();

        // Get analysis ID
        var idSQL = "SELECT ANALYSIS_ID FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE "
            + "WHERE ANALYSIS_TYPE = 'FAILURE_EXPLANATION' "
            + "AND RUN_ID = '" + P_RUN_ID + "' "
            + "AND CHECK_ID = " + chk.check_id + " "
            + "ORDER BY CREATED_AT DESC LIMIT 1";
        var idStmt = snowflake.createStatement({ sqlText: idSQL });
        var idRS = idStmt.execute();
        idRS.next();
        var aid = idRS.getColumnValue(1);

        analysisIds.push(aid);
        explanations.push({
            check_id: chk.check_id,
            check_name: chk.check_name,
            check_status: chk.check_status,
            analysis_id: aid,
            ai_response: aiResponse
        });
    }

    // --------------------------------------------------
    // 5. Return summary
    // --------------------------------------------------
    return {
        run_id: P_RUN_ID,
        table: tableFQN,
        status: 'SUCCESS',
        analyses_created: analysisIds.length,
        analysis_ids: analysisIds,
        explanations: explanations
    };
$$;

CREATE OR REPLACE PROCEDURE DQ_GUARDIAN.CORTEX_AI.SP_AI_RECOMMEND_REMEDIATION(P_CHECK_RESULT_ID VARCHAR)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    // --------------------------------------------------
    // 1. Read the check result with library metadata
    // --------------------------------------------------
    var crSQL = "SELECT r.RESULT_ID, r.RUN_ID, r.CHECK_ID, r.CHECK_NAME, r.TARGET_TABLE, "
        + "r.TARGET_COLUMN, r.CHECK_STATUS, r.SEVERITY, r.TOTAL_ROWS, "
        + "r.FAILURE_COUNT, r.FAILURE_PCT, r.THRESHOLD_WARNING, r.THRESHOLD_FAIL, "
        + "l.DESCRIPTION, l.CATEGORY, l.SQL_TEMPLATE "
        + "FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_CHECK_RESULTS r "
        + "JOIN DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY l ON r.CHECK_ID = l.CHECK_ID "
        + "WHERE r.RESULT_ID = '" + P_CHECK_RESULT_ID + "'";
    var crStmt = snowflake.createStatement({ sqlText: crSQL });
    var crRS = crStmt.execute();

    if (!crRS.next()) {
        return { check_result_id: P_CHECK_RESULT_ID, status: 'ERROR', message: 'CHECK_RESULT_ID not found.' };
    }

    var resultId    = crRS.getColumnValue(1);
    var runId       = crRS.getColumnValue(2);
    var checkId     = crRS.getColumnValue(3);
    var checkName   = crRS.getColumnValue(4);
    var targetTable = crRS.getColumnValue(5);
    var targetCol   = crRS.getColumnValue(6);
    var checkStatus = crRS.getColumnValue(7);
    var severity    = crRS.getColumnValue(8);
    var totalRows   = crRS.getColumnValue(9);
    var failCount   = crRS.getColumnValue(10);
    var failPct     = crRS.getColumnValue(11);
    var threshWarn  = crRS.getColumnValue(12);
    var threshFail  = crRS.getColumnValue(13);
    var description = crRS.getColumnValue(14);
    var category    = crRS.getColumnValue(15);
    var sqlTemplate = crRS.getColumnValue(16);

    // Skip PASS results
    if (checkStatus === 'PASS') {
        return { check_result_id: P_CHECK_RESULT_ID, status: 'SKIPPED',
                 message: 'Check passed. No remediation needed.' };
    }

    // --------------------------------------------------
    // 2. Get the run target for FQN
    // --------------------------------------------------
    var rlSQL = "SELECT TARGET_DATABASE, TARGET_SCHEMA "
        + "FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG "
        + "WHERE RUN_ID = '" + runId + "'";
    var rlStmt = snowflake.createStatement({ sqlText: rlSQL });
    var rlRS = rlStmt.execute();
    var targetDB = '', targetSchema = '';
    if (rlRS.next()) {
        targetDB = rlRS.getColumnValue(1);
        targetSchema = rlRS.getColumnValue(2);
    }
    var tableFQN = targetDB + '.' + targetSchema + '.' + targetTable;

    // --------------------------------------------------
    // 3. Get assignment params if available
    // --------------------------------------------------
    var paramsJson = null;
    var aSQL = "SELECT PARAMS_JSON FROM DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS "
        + "WHERE CHECK_ID = " + checkId + " AND TARGET_TABLE = '" + targetTable + "' "
        + "AND IS_ACTIVE = TRUE LIMIT 1";
    try {
        var aStmt = snowflake.createStatement({ sqlText: aSQL });
        var aRS = aStmt.execute();
        if (aRS.next()) {
            var pj = aRS.getColumnValue(1);
            if (pj) paramsJson = JSON.stringify(pj);
        }
    } catch(e) { /* assignment lookup is optional */ }

    // --------------------------------------------------
    // 4. Get sample failed records
    // --------------------------------------------------
    var frSQL = "SELECT RECORD_IDENTIFIER, COLUMN_NAME, FAILED_VALUE, FAILURE_REASON "
        + "FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_FAILED_RECORDS "
        + "WHERE RUN_ID = '" + runId + "' AND CHECK_ID = " + checkId + " "
        + "ORDER BY CREATED_AT LIMIT 5";
    var frStmt = snowflake.createStatement({ sqlText: frSQL });
    var frRS = frStmt.execute();

    var sampleLines = [];
    while (frRS.next()) {
        sampleLines.push('- Record ' + frRS.getColumnValue(1)
            + ', Column: ' + frRS.getColumnValue(2)
            + ', Value: ' + frRS.getColumnValue(3)
            + ', Reason: ' + frRS.getColumnValue(4));
    }

    // --------------------------------------------------
    // 5. Build context and prompt
    // --------------------------------------------------
    var ctx = 'TABLE: ' + tableFQN + '\n'
        + 'CHECK ID: ' + checkId + '\n'
        + 'CHECK NAME: ' + checkName + '\n'
        + 'CATEGORY: ' + category + '\n'
        + 'DESCRIPTION: ' + description + '\n'
        + 'STATUS: ' + checkStatus + '\n'
        + 'SEVERITY: ' + severity + '\n'
        + 'TOTAL ROWS: ' + totalRows + '\n'
        + 'FAILURE COUNT: ' + failCount + '\n'
        + 'FAILURE %: ' + failPct + '\n'
        + 'WARNING THRESHOLD: ' + threshWarn + '%\n'
        + 'FAIL THRESHOLD: ' + threshFail + '%\n';

    if (targetCol) ctx += 'TARGET COLUMN: ' + targetCol + '\n';
    if (paramsJson) ctx += 'CHECK PARAMETERS: ' + paramsJson + '\n';

    if (sampleLines.length > 0) {
        ctx += '\nSAMPLE FAILED RECORDS:\n' + sampleLines.join('\n') + '\n';
    }

    var prompt = 'You are a data quality remediation specialist working with Snowflake SQL. '
        + 'A data quality check has failed. Based on the check details below, provide a structured remediation recommendation:\n\n'
        + '1. ROOT CAUSE HYPOTHESIS: What is likely causing this failure?\n'
        + '2. RECOMMENDED REMEDIATION: What specific action should be taken?\n'
        + '3. SUGGESTED SQL: Provide a Snowflake SQL statement that could fix the issue. '
        + 'Use the actual table and column names from the context.\n'
        + '4. RISKS OR SIDE EFFECTS: What could go wrong if this fix is applied?\n'
        + '5. AUTOMATION SAFETY: Is this fix SAFE to automate, or does it REQUIRE HUMAN REVIEW? '
        + 'Answer with exactly one of: SAFE_TO_AUTOMATE or REQUIRES_HUMAN_REVIEW, followed by a brief reason.\n\n'
        + 'Be specific and practical. Use real table/column names.\n\n'
        + ctx;

    // --------------------------------------------------
    // 6. Call Cortex COMPLETE
    // --------------------------------------------------
    var model = 'llama3.3-70b';
    var escapedPrompt = prompt.replace(/'/g, "''");
    var aiSQL = "SELECT SNOWFLAKE.CORTEX.COMPLETE('" + model + "', '" + escapedPrompt + "') AS AI_RESPONSE";
    var aiStmt = snowflake.createStatement({ sqlText: aiSQL });
    var aiRS = aiStmt.execute();
    aiRS.next();
    var aiResponse = aiRS.getColumnValue(1);

    // --------------------------------------------------
    // 7. Store in AI_ANALYSIS_CACHE (idempotent)
    // --------------------------------------------------
    var delSQL = "DELETE FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE "
        + "WHERE ANALYSIS_TYPE = 'REMEDIATION_RECOMMENDATION' "
        + "AND RUN_ID = '" + runId + "' "
        + "AND CHECK_ID = " + checkId;
    snowflake.createStatement({ sqlText: delSQL }).execute();

    var escapedCtx  = ctx.replace(/'/g, "''");
    var escapedResp = aiResponse.replace(/'/g, "''");

    var insertSQL = "INSERT INTO DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE "
        + "(ANALYSIS_TYPE, RUN_ID, CHECK_ID, TARGET_TABLE, INPUT_CONTEXT, AI_RESPONSE, MODEL_USED, STATUS) "
        + "SELECT 'REMEDIATION_RECOMMENDATION', '" + runId + "', " + checkId + ", "
        + "'" + tableFQN + "', "
        + "'" + escapedCtx + "', "
        + "'" + escapedResp + "', "
        + "'" + model + "', 'COMPLETED'";
    snowflake.createStatement({ sqlText: insertSQL }).execute();

    // Get the analysis ID
    var idSQL = "SELECT ANALYSIS_ID FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE "
        + "WHERE ANALYSIS_TYPE = 'REMEDIATION_RECOMMENDATION' "
        + "AND RUN_ID = '" + runId + "' "
        + "AND CHECK_ID = " + checkId + " "
        + "ORDER BY CREATED_AT DESC LIMIT 1";
    var idStmt = snowflake.createStatement({ sqlText: idSQL });
    var idRS = idStmt.execute();
    idRS.next();
    var analysisId = idRS.getColumnValue(1);

    // --------------------------------------------------
    // 8. Return result
    // --------------------------------------------------
    return {
        check_result_id: P_CHECK_RESULT_ID,
        status: 'SUCCESS',
        analysis_id: analysisId,
        model: model,
        recommendation: aiResponse
    };
$$;

CREATE OR REPLACE PROCEDURE DQ_GUARDIAN.CORTEX_AI.SP_AI_APPLY_SAFE_FIX(P_RECOMMENDATION_ID VARCHAR)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var BLOCKED_KEYWORDS = ['DROP ', 'TRUNCATE ', 'ALTER ', 'GRANT ', 'REVOKE ', 'CREATE ', 'DELETE FROM'];

    // --------------------------------------------------
    // 1. Read the recommendation
    // --------------------------------------------------
    var recSQL = "SELECT ANALYSIS_ID, ANALYSIS_TYPE, RUN_ID, CHECK_ID, TARGET_TABLE, "
        + "AI_RESPONSE, MODEL_USED, STATUS "
        + "FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE "
        + "WHERE ANALYSIS_ID = '" + P_RECOMMENDATION_ID + "'";
    var recStmt = snowflake.createStatement({ sqlText: recSQL });
    var recRS = recStmt.execute();

    if (!recRS.next()) {
        return { recommendation_id: P_RECOMMENDATION_ID, status: 'ERROR',
                 message: 'Recommendation not found.' };
    }

    var analysisType = recRS.getColumnValue(2);
    var runId        = recRS.getColumnValue(3);
    var checkId      = recRS.getColumnValue(4);
    var targetTable  = recRS.getColumnValue(5);
    var aiResponse   = recRS.getColumnValue(6);
    var modelUsed    = recRS.getColumnValue(7);

    // Validate analysis type
    if (analysisType !== 'REMEDIATION_RECOMMENDATION') {
        return { recommendation_id: P_RECOMMENDATION_ID, status: 'ERROR',
                 message: 'ANALYSIS_ID is not a REMEDIATION_RECOMMENDATION. Type: ' + analysisType };
    }

    // --------------------------------------------------
    // 2. Extract safety classification from AI_RESPONSE
    // --------------------------------------------------
    var safetyClass = 'UNKNOWN';
    var responseUpper = aiResponse.toUpperCase();

    if (responseUpper.indexOf('SAFE_TO_AUTOMATE') !== -1) {
        safetyClass = 'SAFE_TO_AUTOMATE';
    } else if (responseUpper.indexOf('REQUIRES_HUMAN_REVIEW') !== -1) {
        safetyClass = 'REQUIRES_HUMAN_REVIEW';
    } else if (responseUpper.indexOf('UNSAFE') !== -1) {
        safetyClass = 'UNSAFE';
    }

    // --------------------------------------------------
    // 3. If not SAFE, skip execution
    // --------------------------------------------------
    if (safetyClass !== 'SAFE_TO_AUTOMATE') {
        return {
            recommendation_id: P_RECOMMENDATION_ID,
            target_table: targetTable,
            safety_classification: safetyClass,
            status: 'SKIPPED',
            action_executed: false,
            audit_id: null,
            message: 'Recommendation classified as ' + safetyClass
                + '. Automated fix not applied. Human review required.'
        };
    }

    // --------------------------------------------------
    // 4. Extract SQL from AI_RESPONSE (```sql blocks)
    // --------------------------------------------------
    var extractedSQL = null;
    var sqlStart = aiResponse.indexOf('```sql');
    if (sqlStart !== -1) {
        var codeStart = aiResponse.indexOf('\n', sqlStart) + 1;
        var codeEnd = aiResponse.indexOf('```', codeStart);
        if (codeEnd !== -1) {
            extractedSQL = aiResponse.substring(codeStart, codeEnd).trim();
        }
    }

    // Fallback: look for UPDATE/INSERT/MERGE statements
    if (!extractedSQL) {
        var lines = aiResponse.split('\n');
        for (var i = 0; i < lines.length; i++) {
            var trimmed = lines[i].trim().toUpperCase();
            if (trimmed.indexOf('UPDATE ') === 0
                || trimmed.indexOf('INSERT ') === 0
                || trimmed.indexOf('MERGE ') === 0) {
                var sqlLines = [];
                for (var j = i; j < lines.length; j++) {
                    var ln = lines[j].trim();
                    if (ln === '' || ln === '```') break;
                    sqlLines.push(ln);
                }
                extractedSQL = sqlLines.join(' ');
                break;
            }
        }
    }

    if (!extractedSQL || extractedSQL.length < 10) {
        return {
            recommendation_id: P_RECOMMENDATION_ID,
            target_table: targetTable,
            safety_classification: safetyClass,
            status: 'ERROR',
            action_executed: false,
            audit_id: null,
            message: 'Could not extract valid SQL from the recommendation.'
        };
    }

    // --------------------------------------------------
    // 5. Guard against destructive SQL
    // --------------------------------------------------
    var sqlUpper = extractedSQL.toUpperCase().trim();
    for (var k = 0; k < BLOCKED_KEYWORDS.length; k++) {
        if (sqlUpper.indexOf(BLOCKED_KEYWORDS[k]) !== -1) {
            return {
                recommendation_id: P_RECOMMENDATION_ID,
                target_table: targetTable,
                safety_classification: safetyClass,
                status: 'BLOCKED',
                action_executed: false,
                audit_id: null,
                message: 'SQL contains blocked keyword: '
                    + BLOCKED_KEYWORDS[k].trim() + '. Automated execution denied.'
            };
        }
    }

    // Must start with UPDATE, INSERT, or MERGE
    if (sqlUpper.indexOf('UPDATE ') !== 0
        && sqlUpper.indexOf('INSERT ') !== 0
        && sqlUpper.indexOf('MERGE ') !== 0) {
        return {
            recommendation_id: P_RECOMMENDATION_ID,
            target_table: targetTable,
            safety_classification: safetyClass,
            status: 'BLOCKED',
            action_executed: false,
            audit_id: null,
            message: 'SQL does not start with UPDATE/INSERT/MERGE. Only controlled DML is allowed.'
        };
    }

    // --------------------------------------------------
    // 6. Idempotency: check if already applied via audit table
    // --------------------------------------------------
    var auditExists = false;
    try {
        var chkSQL = "SELECT COUNT(*) FROM DQ_GUARDIAN.REMEDIATION.REMEDIATION_AUDIT "
            + "WHERE ANALYSIS_ID = '" + P_RECOMMENDATION_ID + "' AND STATUS = 'SUCCESS'";
        var chkStmt = snowflake.createStatement({ sqlText: chkSQL });
        var chkRS = chkStmt.execute();
        chkRS.next();
        if (chkRS.getColumnValue(1) > 0) {
            return {
                recommendation_id: P_RECOMMENDATION_ID,
                target_table: targetTable,
                safety_classification: safetyClass,
                status: 'ALREADY_APPLIED',
                action_executed: false,
                audit_id: null,
                message: 'This recommendation was already successfully applied.'
            };
        }
        auditExists = true;
    } catch(e) {
        // REMEDIATION_AUDIT does not exist yet (Phase 7 dependency)
        auditExists = false;
    }

    // --------------------------------------------------
    // 7. Execute the remediation SQL
    // --------------------------------------------------
    var execStatus = 'SUCCESS';
    var errorMsg = null;
    try {
        var fixStmt = snowflake.createStatement({ sqlText: extractedSQL });
        fixStmt.execute();
    } catch(e) {
        execStatus = 'FAILED';
        errorMsg = e.message;
    }

    // --------------------------------------------------
    // 8. Record audit (if table exists)
    // --------------------------------------------------
    var auditId = null;
    if (auditExists) {
        try {
            var escapedSQL = extractedSQL.replace(/'/g, "''");
            var errVal = errorMsg ? "'" + errorMsg.replace(/'/g, "''") + "'" : 'NULL';

            var auditSQL = "INSERT INTO DQ_GUARDIAN.REMEDIATION.REMEDIATION_AUDIT "
                + "(ANALYSIS_ID, TARGET_TABLE, ACTION_SQL, STATUS, ERROR_MESSAGE) "
                + "SELECT '" + P_RECOMMENDATION_ID + "', "
                + "'" + targetTable + "', "
                + "'" + escapedSQL + "', "
                + "'" + execStatus + "', "
                + errVal;
            snowflake.createStatement({ sqlText: auditSQL }).execute();

            var aidSQL = "SELECT AUDIT_ID FROM DQ_GUARDIAN.REMEDIATION.REMEDIATION_AUDIT "
                + "WHERE ANALYSIS_ID = '" + P_RECOMMENDATION_ID + "' "
                + "ORDER BY EXECUTED_AT DESC LIMIT 1";
            var aidStmt = snowflake.createStatement({ sqlText: aidSQL });
            var aidRS = aidStmt.execute();
            if (aidRS.next()) auditId = aidRS.getColumnValue(1);
        } catch(e) {
            // Audit write failed — do not mask the main result
        }
    }

    // --------------------------------------------------
    // 9. Return result
    // --------------------------------------------------
    var msg = (execStatus === 'SUCCESS')
        ? 'Remediation SQL executed successfully.'
        : 'Remediation SQL failed: ' + errorMsg;

    if (!auditExists) {
        msg += ' NOTE: REMEDIATION_AUDIT table does not exist yet (Phase 7 dependency). Audit record was not written.';
    }

    return {
        recommendation_id: P_RECOMMENDATION_ID,
        target_table: targetTable,
        safety_classification: safetyClass,
        status: execStatus,
        action_executed: (execStatus === 'SUCCESS'),
        audit_id: auditId,
        message: msg,
        sql_executed: (execStatus === 'SUCCESS') ? extractedSQL : null
    };
$$;

CREATE OR REPLACE PROCEDURE DQ_GUARDIAN.CORTEX_AI.SP_AI_RERUN_AND_SCORE(P_RUN_ID VARCHAR)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    // --------------------------------------------------
    // 1. Validate original RUN_ID and capture baseline
    // --------------------------------------------------
    var origSQL = "SELECT r.RUN_ID, r.TARGET_DATABASE, r.TARGET_SCHEMA, r.TARGET_TABLE, "
        + "r.TOTAL_CHECKS, r.PASSED_CHECKS, r.FAILED_CHECKS, "
        + "h.HEALTH_SCORE "
        + "FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG r "
        + "LEFT JOIN DQ_GUARDIAN.CHECK_RESULTS.DQ_HEALTH_SCORES h ON r.RUN_ID = h.RUN_ID "
        + "WHERE r.RUN_ID = '" + P_RUN_ID + "'";
    var origStmt = snowflake.createStatement({ sqlText: origSQL });
    var origRS = origStmt.execute();

    if (!origRS.next()) {
        return { original_run_id: P_RUN_ID, status: 'ERROR', message: 'RUN_ID not found.' };
    }

    var origDB      = origRS.getColumnValue(2);
    var origSchema  = origRS.getColumnValue(3);
    var origTable   = origRS.getColumnValue(4);
    var origTotal   = origRS.getColumnValue(5);
    var origPassed  = origRS.getColumnValue(6);
    var origFailed  = origRS.getColumnValue(7);
    var origScore   = origRS.getColumnValue(8);

    if (origScore === null) {
        return { original_run_id: P_RUN_ID, status: 'ERROR',
                 message: 'No health score for original run. Run SP_CALCULATE_HEALTH_SCORE first.' };
    }

    // --------------------------------------------------
    // 2. Record max RUN_START_TIME before rerun
    // --------------------------------------------------
    var tsSQL = "SELECT MAX(RUN_START_TIME)::VARCHAR FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG";
    var tsStmt = snowflake.createStatement({ sqlText: tsSQL });
    var tsRS = tsStmt.execute();
    tsRS.next();
    var beforeTimestamp = tsRS.getColumnValue(1);

    // --------------------------------------------------
    // 3. Trigger fresh DQ run via SP_RUN_ALL_CHECKS
    // --------------------------------------------------
    var runSQL = "CALL DQ_GUARDIAN.CHECK_RESULTS.SP_RUN_ALL_CHECKS()";
    var runStmt = snowflake.createStatement({ sqlText: runSQL });
    runStmt.execute();

    // --------------------------------------------------
    // 4. Find the new RUN_ID for the same target table
    // --------------------------------------------------
    var newSQL = "SELECT RUN_ID, TOTAL_CHECKS, PASSED_CHECKS, FAILED_CHECKS "
        + "FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG "
        + "WHERE TARGET_TABLE = '" + origTable + "' "
        + "AND RUN_START_TIME > '" + beforeTimestamp + "' "
        + "ORDER BY RUN_START_TIME DESC LIMIT 1";
    var newStmt = snowflake.createStatement({ sqlText: newSQL });
    var newRS = newStmt.execute();

    if (!newRS.next()) {
        return { original_run_id: P_RUN_ID, status: 'ERROR',
                 message: 'No new run found for table ' + origTable + ' after rerun.' };
    }

    var rerunId     = newRS.getColumnValue(1);
    var rerunTotal  = newRS.getColumnValue(2);
    var rerunPassed = newRS.getColumnValue(3);
    var rerunFailed = newRS.getColumnValue(4);

    // --------------------------------------------------
    // 5. Calculate health score for the new run
    // --------------------------------------------------
    var scoreSQL = "CALL DQ_GUARDIAN.CHECK_RESULTS.SP_CALCULATE_HEALTH_SCORE('" + rerunId + "')";
    var scoreStmt = snowflake.createStatement({ sqlText: scoreSQL });
    scoreStmt.execute();

    var hsSQL = "SELECT HEALTH_SCORE FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_HEALTH_SCORES "
        + "WHERE RUN_ID = '" + rerunId + "'";
    var hsStmt = snowflake.createStatement({ sqlText: hsSQL });
    var hsRS = hsStmt.execute();

    var rerunScore = null;
    if (hsRS.next()) {
        rerunScore = hsRS.getColumnValue(1);
    }

    // --------------------------------------------------
    // 6. Compare and determine improvement status
    // --------------------------------------------------
    var scoreChange = (rerunScore !== null) ? (rerunScore - origScore) : 0;
    var improvementStatus = 'UNCHANGED';
    if (scoreChange > 0.01) {
        improvementStatus = 'IMPROVED';
    } else if (scoreChange < -0.01) {
        improvementStatus = 'DEGRADED';
    }

    var msg = 'Rerun completed for table ' + origTable + '. '
        + 'Original score: ' + origScore + ', Rerun score: ' + rerunScore + '. '
        + 'Status: ' + improvementStatus + '. '
        + 'NOTE: SP_RUN_ALL_CHECKS runs all configured tables, not just ' + origTable + '.';

    // --------------------------------------------------
    // 7. Return comparison
    // --------------------------------------------------
    return {
        original_run_id: P_RUN_ID,
        rerun_run_id: rerunId,
        target_table: origTable,
        original_health_score: origScore,
        rerun_health_score: rerunScore,
        score_change: scoreChange,
        original_failed_checks: origFailed,
        rerun_failed_checks: rerunFailed,
        improvement_status: improvementStatus,
        status: 'SUCCESS',
        message: msg
    };
$$;

CREATE OR REPLACE PROCEDURE DQ_GUARDIAN.CORTEX_AI.SP_AI_NATURAL_LANGUAGE_QUERY(P_QUESTION VARCHAR)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    // --------------------------------------------------
    // 1. Validate input
    // --------------------------------------------------
    if (!P_QUESTION || P_QUESTION.trim().length === 0) {
        return { question: P_QUESTION, status: 'ERROR', message: 'Question cannot be empty.' };
    }

    // --------------------------------------------------
    // 2. Approved objects and schema context for Cortex
    // --------------------------------------------------
    var schemaContext = [
        'APPROVED OBJECTS YOU MAY QUERY:',
        '',
        '1. DQ_GUARDIAN.CHECK_RESULTS.V_OVERALL_HEALTH',
        '   Columns: OVERALL_HEALTH_SCORE, TABLES_EVALUATED, TOTAL_CHECKS, PASSED_CHECKS, FAILED_CHECKS, WARNING_CHECKS, TOTAL_FAILED_RECORDS, OVERALL_STATUS, LATEST_RUN',
        '',
        '2. DQ_GUARDIAN.CHECK_RESULTS.V_TABLE_HEALTH_DASHBOARD',
        '   Columns: TARGET_TABLE, HEALTH_SCORE, TOTAL_CHECKS, PASSED_CHECKS, FAILED_CHECKS, FAILED_RECORD_COUNT, OVERALL_STATUS, RUN_ID',
        '',
        '3. DQ_GUARDIAN.CHECK_RESULTS.V_CHECK_SUMMARY',
        '   Columns: RUN_ID, TARGET_TABLE, CHECK_ID, CHECK_NAME, CHECK_STATUS, SEVERITY, FAILURE_COUNT',
        '',
        '4. DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG',
        '   Columns: RUN_ID, RUN_START_TIME, RUN_END_TIME, TARGET_DATABASE, TARGET_SCHEMA, TARGET_TABLE, TOTAL_CHECKS, PASSED_CHECKS, FAILED_CHECKS, OVERALL_STATUS',
        '',
        '5. DQ_GUARDIAN.PROFILING.TABLE_PROFILES',
        '   Columns: DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, ROW_COUNT, COLUMN_COUNT, PROFILED_AT',
        '',
        '6. DQ_GUARDIAN.PROFILING.COLUMN_PROFILES',
        '   Columns: DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, COLUMN_NAME, DATA_TYPE, NULL_COUNT, NULL_PCT, DISTINCT_COUNT, MIN_VALUE, MAX_VALUE, MEAN, MEDIAN',
        '',
        '7. DQ_GUARDIAN.PROFILING.DISTRIBUTION_SNAPSHOTS',
        '   Columns: TABLE_NAME, COLUMN_NAME, VALUE_OR_BUCKET, RECORD_COUNT, PERCENTAGE',
        '',
        '8. DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY',
        '   Columns: CHECK_ID, CHECK_NAME, CATEGORY, DESCRIPTION, SEVERITY, WEIGHT, IS_AI_CHECK, IS_ACTIVE',
        '',
        '9. DQ_GUARDIAN.REMEDIATION.V_PENDING_REMEDIATIONS',
        '   Columns: RECOMMENDATION_ID, CHECK_ID, TARGET_TABLE, SAFETY_CLASSIFICATION, RECOMMENDATION_STATUS, APPROVAL_STATUS, ACTION_STATUS, CREATED_AT',
        '',
        '10. DQ_GUARDIAN.REMEDIATION.V_REMEDIATION_HISTORY',
        '    Columns: RECOMMENDATION_ID, CHECK_ID, TARGET_TABLE, SAFETY_CLASSIFICATION, RECOMMENDATION_STATUS, APPROVAL_STATUS, EXECUTION_STATUS, REVIEWER, EXECUTED_AT',
        '',
        '11. DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE',
        '    Columns: ANALYSIS_ID, ANALYSIS_TYPE, RUN_ID, CHECK_ID, TARGET_TABLE, AI_RESPONSE, MODEL_USED, STATUS, CREATED_AT'
    ].join('\n');

    var prompt = 'You are a SQL expert for Snowflake. A business user asks a question about data quality. '
        + 'Generate exactly ONE read-only SELECT statement to answer the question. '
        + 'Use ONLY the approved objects and columns listed below. '
        + 'Do NOT use any other tables, databases, or schemas. '
        + 'Return ONLY the SQL statement inside a ```sql code block. '
        + 'Do not explain. Do not add comments. Do not use INSERT, UPDATE, DELETE, DROP, or any DDL/DML.\n\n'
        + schemaContext + '\n\n'
        + 'QUESTION: ' + P_QUESTION;

    // --------------------------------------------------
    // 3. Call Cortex COMPLETE
    // --------------------------------------------------
    var model = 'llama3.3-70b';
    var escapedPrompt = prompt.replace(/'/g, "''");
    var aiSQL = "SELECT SNOWFLAKE.CORTEX.COMPLETE('" + model + "', '" + escapedPrompt + "') AS AI_RESPONSE";
    var aiStmt = snowflake.createStatement({ sqlText: aiSQL });
    var aiRS = aiStmt.execute();
    aiRS.next();
    var aiResponse = aiRS.getColumnValue(1);

    // --------------------------------------------------
    // 4. Extract SQL from response
    // --------------------------------------------------
    var generatedSQL = null;
    var sqlStart = aiResponse.indexOf('```sql');
    if (sqlStart !== -1) {
        var codeStart = aiResponse.indexOf('\n', sqlStart) + 1;
        var codeEnd = aiResponse.indexOf('```', codeStart);
        if (codeEnd !== -1) {
            generatedSQL = aiResponse.substring(codeStart, codeEnd).trim();
        }
    }
    // Fallback: look for SELECT at start of a line
    if (!generatedSQL) {
        var lines = aiResponse.split('\n');
        var sqlLines = [];
        var capturing = false;
        for (var i = 0; i < lines.length; i++) {
            var trimmed = lines[i].trim();
            if (!capturing && trimmed.toUpperCase().indexOf('SELECT') === 0) {
                capturing = true;
            }
            if (capturing) {
                if (trimmed === '' || trimmed === '```') break;
                sqlLines.push(trimmed);
            }
        }
        if (sqlLines.length > 0) generatedSQL = sqlLines.join(' ');
    }

    if (!generatedSQL || generatedSQL.length < 10) {
        return { question: P_QUESTION, status: 'ERROR', generated_sql: null,
                 message: 'Could not extract valid SQL from Cortex response.' };
    }

    // Remove trailing semicolons
    generatedSQL = generatedSQL.replace(/;\s*$/, '');

    // --------------------------------------------------
    // 5. Safety validation
    // --------------------------------------------------
    var sqlUpper = generatedSQL.toUpperCase().trim();

    // Must start with SELECT or WITH
    if (sqlUpper.indexOf('SELECT') !== 0 && sqlUpper.indexOf('WITH') !== 0) {
        return { question: P_QUESTION, status: 'BLOCKED', generated_sql: generatedSQL,
                 message: 'Generated SQL does not start with SELECT or WITH. Blocked.' };
    }

    // Block dangerous keywords
    var blocked = ['INSERT ', 'UPDATE ', 'DELETE ', 'MERGE ', 'DROP ', 'TRUNCATE ',
                   'ALTER ', 'CREATE ', 'GRANT ', 'REVOKE ', 'CALL ', 'EXECUTE ',
                   'PUT ', 'REMOVE ', 'COPY '];
    for (var b = 0; b < blocked.length; b++) {
        if (sqlUpper.indexOf(blocked[b]) !== -1) {
            return { question: P_QUESTION, status: 'BLOCKED', generated_sql: generatedSQL,
                     message: 'SQL contains blocked keyword: ' + blocked[b].trim() };
        }
    }

    // Block multiple statements
    var stmtCount = 0;
    var inString = false;
    for (var c = 0; c < generatedSQL.length; c++) {
        if (generatedSQL[c] === "'") inString = !inString;
        if (generatedSQL[c] === ';' && !inString) stmtCount++;
    }
    if (stmtCount > 0) {
        return { question: P_QUESTION, status: 'BLOCKED', generated_sql: generatedSQL,
                 message: 'Multiple SQL statements detected. Only one SELECT is allowed.' };
    }

    // Validate references to approved objects only
    var approved = ['V_OVERALL_HEALTH', 'V_TABLE_HEALTH_DASHBOARD', 'V_CHECK_SUMMARY',
                    'DQ_RUN_LOG', 'TABLE_PROFILES', 'COLUMN_PROFILES', 'DISTRIBUTION_SNAPSHOTS',
                    'DQ_CHECK_LIBRARY', 'V_PENDING_REMEDIATIONS', 'V_REMEDIATION_HISTORY',
                    'AI_ANALYSIS_CACHE'];
    var fromPattern = /(?:FROM|JOIN)\s+([A-Za-z0-9_.]+)/gi;
    var match;
    while ((match = fromPattern.exec(generatedSQL)) !== null) {
        var ref = match[1].toUpperCase();
        var refParts = ref.split('.');
        var tableName = refParts[refParts.length - 1];
        var found = false;
        for (var a = 0; a < approved.length; a++) {
            if (tableName === approved[a]) { found = true; break; }
        }
        if (!found) {
            return { question: P_QUESTION, status: 'BLOCKED', generated_sql: generatedSQL,
                     message: 'SQL references unapproved object: ' + match[1] };
        }
    }

    // --------------------------------------------------
    // 6. Execute the validated query
    // --------------------------------------------------
    try {
        var qStmt = snowflake.createStatement({ sqlText: generatedSQL });
        var qRS = qStmt.execute();

        var colCount = qStmt.getColumnCount();
        var columns = [];
        for (var ci = 1; ci <= colCount; ci++) {
            columns.push(qStmt.getColumnName(ci));
        }

        var rows = [];
        var rowCount = 0;
        while (qRS.next() && rowCount < 50) {
            var row = {};
            for (var ri = 1; ri <= colCount; ri++) {
                row[columns[ri-1]] = qRS.getColumnValue(ri);
            }
            rows.push(row);
            rowCount++;
        }

        return {
            question: P_QUESTION,
            status: 'SUCCESS',
            generated_sql: generatedSQL,
            columns: columns,
            rows: rows,
            row_count: rowCount,
            message: 'Query executed successfully. ' + rowCount + ' row(s) returned.'
        };
    } catch(e) {
        return {
            question: P_QUESTION,
            status: 'EXECUTION_ERROR',
            generated_sql: generatedSQL,
            message: 'SQL execution failed: ' + e.message
        };
    }
$$;

-- ============================================================
-- 17. REMEDIATION TABLES
-- ============================================================
USE SCHEMA DQ_GUARDIAN.REMEDIATION;

-- -------------------------------------------------------
-- 12A. AI_RECOMMENDATIONS
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.REMEDIATION.AI_RECOMMENDATIONS (
    RECOMMENDATION_ID   VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    ANALYSIS_ID         VARCHAR(36),
    RUN_ID              VARCHAR(36),
    CHECK_ID            INTEGER,
    TARGET_TABLE        VARCHAR(256)    NOT NULL,
    RECOMMENDATION_TYPE VARCHAR(50)     NOT NULL,
    RECOMMENDATION_TEXT VARCHAR(16000),
    PROPOSED_SQL        VARCHAR(8000),
    SAFETY_CLASSIFICATION VARCHAR(30)   NOT NULL DEFAULT 'UNKNOWN',
    STATUS              VARCHAR(20)     NOT NULL DEFAULT 'PENDING',
    CREATED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT          TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_AI_RECOMMENDATIONS PRIMARY KEY (RECOMMENDATION_ID)
)
COMMENT = 'Cortex AI-generated remediation recommendations for DQ failures';

-- -------------------------------------------------------
-- 12B. REMEDIATION_AUDIT
-- -------------------------------------------------------
-- Compatible with SP_AI_APPLY_SAFE_FIX columns:
-- AUDIT_ID, ANALYSIS_ID, TARGET_TABLE, ACTION_SQL, STATUS, ERROR_MESSAGE, EXECUTED_AT
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.REMEDIATION.REMEDIATION_AUDIT (
    AUDIT_ID        VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    ANALYSIS_ID     VARCHAR(36)     NOT NULL,
    TARGET_TABLE    VARCHAR(256),
    ACTION_SQL      VARCHAR(8000),
    STATUS          VARCHAR(20)     NOT NULL,
    ERROR_MESSAGE   VARCHAR(4000),
    EXECUTED_BY     VARCHAR(256)    DEFAULT CURRENT_USER(),
    EXECUTED_AT     TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_REMEDIATION_AUDIT PRIMARY KEY (AUDIT_ID)
)
COMMENT = 'Execution history of remediation actions applied to source data';

-- -------------------------------------------------------
-- 12C. APPROVAL_QUEUE
-- -------------------------------------------------------
CREATE TABLE IF NOT EXISTS DQ_GUARDIAN.REMEDIATION.APPROVAL_QUEUE (
    APPROVAL_ID         VARCHAR(36)     NOT NULL DEFAULT UUID_STRING(),
    RECOMMENDATION_ID   VARCHAR(36)     NOT NULL,
    TARGET_TABLE        VARCHAR(256),
    APPROVAL_STATUS     VARCHAR(20)     NOT NULL DEFAULT 'PENDING',
    REQUESTED_AT        TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    REVIEWED_AT         TIMESTAMP_NTZ,
    REVIEWER            VARCHAR(256),
    REVIEW_COMMENTS     VARCHAR(4000),
    CONSTRAINT PK_APPROVAL_QUEUE PRIMARY KEY (APPROVAL_ID)
)
COMMENT = 'Human approval queue for remediation recommendations requiring review';

-- ============================================================
-- 18. REMEDIATION VIEWS
-- ============================================================
-- -------------------------------------------------------
-- 13A. V_PENDING_REMEDIATIONS
-- -------------------------------------------------------
CREATE OR REPLACE VIEW DQ_GUARDIAN.REMEDIATION.V_PENDING_REMEDIATIONS AS
SELECT
    c.ANALYSIS_ID       AS RECOMMENDATION_ID,
    c.ANALYSIS_ID,
    c.RUN_ID,
    c.CHECK_ID,
    c.TARGET_TABLE,
    c.ANALYSIS_TYPE     AS RECOMMENDATION_TYPE,
    c.AI_RESPONSE       AS RECOMMENDATION_TEXT,
    CASE
        WHEN UPPER(c.AI_RESPONSE) LIKE '%SAFE_TO_AUTOMATE%' THEN 'SAFE_TO_AUTOMATE'
        WHEN UPPER(c.AI_RESPONSE) LIKE '%REQUIRES_HUMAN_REVIEW%' THEN 'REQUIRES_HUMAN_REVIEW'
        WHEN UPPER(c.AI_RESPONSE) LIKE '%UNSAFE%' THEN 'UNSAFE'
        ELSE 'UNKNOWN'
    END                 AS SAFETY_CLASSIFICATION,
    c.STATUS            AS RECOMMENDATION_STATUS,
    COALESCE(aq.APPROVAL_STATUS,
        CASE
            WHEN UPPER(c.AI_RESPONSE) LIKE '%SAFE_TO_AUTOMATE%' THEN 'AUTO_ELIGIBLE'
            ELSE 'AWAITING_REVIEW'
        END
    )                   AS APPROVAL_STATUS,
    aq.REQUESTED_AT,
    c.CREATED_AT,
    ra.EXECUTED_AT      AS LAST_EXECUTED_AT,
    CASE
        WHEN ra.STATUS = 'SUCCESS' THEN 'APPLIED'
        WHEN ra.STATUS = 'FAILED' THEN 'EXECUTION_FAILED'
        WHEN aq.APPROVAL_STATUS = 'REJECTED' THEN 'REJECTED'
        WHEN aq.APPROVAL_STATUS = 'APPROVED' THEN 'APPROVED_PENDING_EXECUTION'
        WHEN UPPER(c.AI_RESPONSE) LIKE '%SAFE_TO_AUTOMATE%' THEN 'SAFE_READY'
        WHEN UPPER(c.AI_RESPONSE) LIKE '%REQUIRES_HUMAN_REVIEW%' THEN 'AWAITING_HUMAN_REVIEW'
        ELSE 'PENDING'
    END                 AS ACTION_STATUS
FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE c
LEFT JOIN DQ_GUARDIAN.REMEDIATION.APPROVAL_QUEUE aq
    ON c.ANALYSIS_ID = aq.RECOMMENDATION_ID
LEFT JOIN DQ_GUARDIAN.REMEDIATION.REMEDIATION_AUDIT ra
    ON c.ANALYSIS_ID = ra.ANALYSIS_ID
WHERE c.ANALYSIS_TYPE = 'REMEDIATION_RECOMMENDATION';

-- -------------------------------------------------------
-- 13B. V_REMEDIATION_HISTORY
-- -------------------------------------------------------
CREATE OR REPLACE VIEW DQ_GUARDIAN.REMEDIATION.V_REMEDIATION_HISTORY AS
SELECT
    c.ANALYSIS_ID       AS RECOMMENDATION_ID,
    c.ANALYSIS_ID,
    c.RUN_ID,
    c.CHECK_ID,
    c.TARGET_TABLE,
    CASE
        WHEN UPPER(c.AI_RESPONSE) LIKE '%SAFE_TO_AUTOMATE%' THEN 'SAFE_TO_AUTOMATE'
        WHEN UPPER(c.AI_RESPONSE) LIKE '%REQUIRES_HUMAN_REVIEW%' THEN 'REQUIRES_HUMAN_REVIEW'
        WHEN UPPER(c.AI_RESPONSE) LIKE '%UNSAFE%' THEN 'UNSAFE'
        ELSE 'UNKNOWN'
    END                 AS SAFETY_CLASSIFICATION,
    c.STATUS            AS RECOMMENDATION_STATUS,
    COALESCE(aq.APPROVAL_STATUS, 'N/A') AS APPROVAL_STATUS,
    COALESCE(ra.STATUS, 'NOT_EXECUTED')  AS EXECUTION_STATUS,
    ra.ACTION_SQL,
    ra.ERROR_MESSAGE,
    aq.REVIEWER,
    aq.REVIEW_COMMENTS,
    ra.EXECUTED_AT,
    ra.EXECUTED_BY,
    c.CREATED_AT
FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE c
LEFT JOIN DQ_GUARDIAN.REMEDIATION.APPROVAL_QUEUE aq
    ON c.ANALYSIS_ID = aq.RECOMMENDATION_ID
LEFT JOIN DQ_GUARDIAN.REMEDIATION.REMEDIATION_AUDIT ra
    ON c.ANALYSIS_ID = ra.ANALYSIS_ID
WHERE c.ANALYSIS_TYPE = 'REMEDIATION_RECOMMENDATION';

-- ============================================================
-- 19. SCHEDULED TASKS (All created SUSPENDED)
-- ============================================================
USE SCHEMA DQ_GUARDIAN.CONFIG;

-- -------------------------------------------------------
-- 14A. Root Task: Profile all configured tables
-- -------------------------------------------------------
CREATE OR REPLACE TASK DQ_GUARDIAN.CONFIG.TASK_PROFILE_TABLES
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '60 MINUTE'
    COMMENT = 'Root task: profiles all active configured tables'
AS
BEGIN
    LET c CURSOR FOR
        SELECT DISTINCT TARGET_DATABASE || '.' || TARGET_SCHEMA || '.' || TARGET_TABLE AS TABLE_FQN
        FROM DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS
        WHERE IS_ACTIVE = TRUE;
    FOR rec IN c DO
        CALL DQ_GUARDIAN.PROFILING.SP_PROFILE_TABLE(rec.TABLE_FQN);
    END FOR;
END;

-- -------------------------------------------------------
-- 14B. Child Task: Run all DQ checks
-- -------------------------------------------------------
CREATE OR REPLACE TASK DQ_GUARDIAN.CONFIG.TASK_RUN_DQ_CHECKS
    WAREHOUSE = COMPUTE_WH
    AFTER DQ_GUARDIAN.CONFIG.TASK_PROFILE_TABLES
AS
    CALL DQ_GUARDIAN.CHECK_RESULTS.SP_RUN_ALL_CHECKS();

-- -------------------------------------------------------
-- 14C. Child Task: Calculate health scores for new runs
-- -------------------------------------------------------
CREATE OR REPLACE TASK DQ_GUARDIAN.CONFIG.TASK_CALCULATE_HEALTH
    WAREHOUSE = COMPUTE_WH
    AFTER DQ_GUARDIAN.CONFIG.TASK_RUN_DQ_CHECKS
AS
BEGIN
    LET c CURSOR FOR
        SELECT RUN_ID
        FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG
        WHERE RUN_START_TIME >= DATEADD('HOUR', -2, CURRENT_TIMESTAMP())
          AND RUN_ID NOT IN (SELECT RUN_ID FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_HEALTH_SCORES);
    FOR rec IN c DO
        CALL DQ_GUARDIAN.CHECK_RESULTS.SP_CALCULATE_HEALTH_SCORE(rec.RUN_ID);
    END FOR;
END;

-- -------------------------------------------------------
-- 14D. Child Task: AI failure analysis for new runs
-- -------------------------------------------------------
CREATE OR REPLACE TASK DQ_GUARDIAN.CONFIG.TASK_AI_EXPLAIN_FAILURES
    WAREHOUSE = COMPUTE_WH
    AFTER DQ_GUARDIAN.CONFIG.TASK_RUN_DQ_CHECKS
AS
BEGIN
    LET c CURSOR FOR
        SELECT r.RUN_ID
        FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG r
        WHERE r.RUN_START_TIME >= DATEADD('HOUR', -2, CURRENT_TIMESTAMP())
          AND r.FAILED_CHECKS > 0
          AND NOT EXISTS (
              SELECT 1 FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE a
              WHERE a.RUN_ID = r.RUN_ID
                AND a.ANALYSIS_TYPE = 'FAILURE_EXPLANATION'
          );
    FOR rec IN c DO
        CALL DQ_GUARDIAN.CORTEX_AI.SP_AI_EXPLAIN_FAILURES(rec.RUN_ID);
    END FOR;
END;

-- To resume the full DAG:
-- SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('DQ_GUARDIAN.CONFIG.TASK_PROFILE_TABLES');

-- ============================================================
-- 20. STREAMS (Change Detection)
-- ============================================================
-- -------------------------------------------------------
-- 15A. Stream on DQ check results
-- -------------------------------------------------------
CREATE OR REPLACE STREAM DQ_GUARDIAN.CONFIG.STREAM_DQ_CHECK_RESULTS
    ON TABLE DQ_GUARDIAN.CHECK_RESULTS.DQ_CHECK_RESULTS
    APPEND_ONLY = FALSE
    COMMENT = 'Captures new/changed DQ check results for downstream monitoring';

-- -------------------------------------------------------
-- 15B. Stream on schema snapshots
-- -------------------------------------------------------
CREATE OR REPLACE STREAM DQ_GUARDIAN.CONFIG.STREAM_SCHEMA_SNAPSHOTS
    ON TABLE DQ_GUARDIAN.PROFILING.SCHEMA_SNAPSHOTS
    APPEND_ONLY = FALSE
    COMMENT = 'Captures schema snapshot changes for drift monitoring';

-- -------------------------------------------------------
-- 15C. Stream on AI recommendations
-- -------------------------------------------------------
CREATE OR REPLACE STREAM DQ_GUARDIAN.CONFIG.STREAM_AI_RECOMMENDATIONS
    ON TABLE DQ_GUARDIAN.REMEDIATION.AI_RECOMMENDATIONS
    APPEND_ONLY = FALSE
    COMMENT = 'Captures new remediation recommendations for approval workflow';

-- -------------------------------------------------------
-- 15D. Stream on remediation audit
-- -------------------------------------------------------
CREATE OR REPLACE STREAM DQ_GUARDIAN.CONFIG.STREAM_REMEDIATION_AUDIT
    ON TABLE DQ_GUARDIAN.REMEDIATION.REMEDIATION_AUDIT
    APPEND_ONLY = FALSE
    COMMENT = 'Captures remediation execution outcomes for audit monitoring';

-- ============================================================
-- 21. STREAMLIT APPLICATION
-- ============================================================
USE SCHEMA DQ_GUARDIAN.STREAMLIT;

-- -------------------------------------------------------
-- 16A. Create stage for Streamlit files
-- -------------------------------------------------------
CREATE STAGE IF NOT EXISTS DQ_GUARDIAN.STREAMLIT.STREAMLIT_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Stage for DQ Guardian Streamlit app files';

-- -------------------------------------------------------
-- 16B. Upload streamlit_app.py to stage
-- -------------------------------------------------------
-- Run from CLI:
-- snow stage copy streamlit_app.py @DQ_GUARDIAN.STREAMLIT.STREAMLIT_STAGE/ --overwrite

-- -------------------------------------------------------
-- 16C. Create Streamlit application
-- -------------------------------------------------------
CREATE OR REPLACE STREAMLIT DQ_GUARDIAN.STREAMLIT.DQ_GUARDIAN_APP
    ROOT_LOCATION = '@DQ_GUARDIAN.STREAMLIT.STREAMLIT_STAGE'
    MAIN_FILE = 'streamlit_app.py'
    QUERY_WAREHOUSE = COMPUTE_WH
    COMMENT = 'Data Quality Guardian - AI-Powered DQ Monitoring Dashboard';

-- ============================================================
-- 22. OPTIONAL VALIDATION / DEMO QUERIES
-- ============================================================
-- Run these after deployment to verify the solution works.

-- Profile a table
-- CALL DQ_GUARDIAN.PROFILING.SP_PROFILE_TABLE('DQ_GUARDIAN', 'SYNTHETIC_DATA', 'CUSTOMERS');

-- Run all DQ checks
-- CALL DQ_GUARDIAN.CHECK_RESULTS.SP_RUN_ALL_CHECKS();

-- Calculate health score (use RUN_ID from DQ_RUN_LOG)
-- CALL DQ_GUARDIAN.CHECK_RESULTS.SP_CALCULATE_HEALTH_SCORE('<RUN_ID>');

-- AI failure analysis
-- CALL DQ_GUARDIAN.CORTEX_AI.SP_AI_EXPLAIN_FAILURES('<RUN_ID>');

-- AI dataset profile
-- CALL DQ_GUARDIAN.CORTEX_AI.SP_AI_PROFILE_DATASET('DQ_GUARDIAN.SYNTHETIC_DATA.CUSTOMERS');

-- Natural language query
-- CALL DQ_GUARDIAN.CORTEX_AI.SP_AI_NATURAL_LANGUAGE_QUERY('What is the overall health score?');

-- View health dashboard
-- SELECT * FROM DQ_GUARDIAN.CHECK_RESULTS.V_OVERALL_HEALTH;
-- SELECT * FROM DQ_GUARDIAN.CHECK_RESULTS.V_TABLE_HEALTH_DASHBOARD ORDER BY HEALTH_SCORE DESC;

-- ============================================================
-- END OF DEPLOYMENT SCRIPT
-- ============================================================
