import streamlit as st
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="DQ Guardian", page_icon="🛡️", layout="wide")

session = get_active_session()

def run_query(sql):
    try:
        return session.sql(sql).to_pandas()
    except Exception as e:
        st.error(f"Query error: {e}")
        return None

# --- SIDEBAR ---
st.sidebar.title("DQ Guardian")
page = st.sidebar.radio("Navigate", [
    "Data Health Dashboard",
    "Profiling Explorer",
    "Check Catalog",
    "Run History & Results",
    "AI Insights",
    "Remediation Center",
    "Natural Language Query",
    "Configuration"
])

# =========================================================
# PAGE 1: DATA HEALTH DASHBOARD
# =========================================================
if page == "Data Health Dashboard":
    st.title("Data Health Dashboard")

    overall = run_query("SELECT * FROM DQ_GUARDIAN.CHECK_RESULTS.V_OVERALL_HEALTH")
    if overall is not None and len(overall) > 0:
        row = overall.iloc[0]
        score = float(row["OVERALL_HEALTH_SCORE"])

        if score >= 80:
            score_color = "🟢"
        elif score >= 50:
            score_color = "🟡"
        else:
            score_color = "🔴"

        c1, c2, c3, c4, c5 = st.columns(5)
        c1.metric("Health Score", f"{score_color} {score:.1f}%")
        c2.metric("Tables Evaluated", int(row["TABLES_EVALUATED"]))
        c3.metric("Total Checks", int(row["TOTAL_CHECKS"]))
        c4.metric("Passed", int(row["PASSED_CHECKS"]))
        c5.metric("Failed", int(row["FAILED_CHECKS"]))

        st.markdown(f"**Overall Status:** `{row['OVERALL_STATUS']}`")
    else:
        st.info("No health data available. Run DQ checks first.")

    st.subheader("Table Health Scores")
    table_health = run_query("""
        SELECT TARGET_TABLE, HEALTH_SCORE, TOTAL_CHECKS, PASSED_CHECKS,
               FAILED_CHECKS, FAILED_RECORD_COUNT, OVERALL_STATUS
        FROM DQ_GUARDIAN.CHECK_RESULTS.V_TABLE_HEALTH_DASHBOARD
        ORDER BY HEALTH_SCORE DESC
    """)
    if table_health is not None and len(table_health) > 0:
        st.dataframe(table_health, use_container_width=True)

        st.subheader("Health Score by Table")
        chart_data = table_health[["TARGET_TABLE", "HEALTH_SCORE"]].set_index("TARGET_TABLE")
        st.bar_chart(chart_data)
    else:
        st.info("No table health data available.")

# =========================================================
# PAGE 2: PROFILING EXPLORER
# =========================================================
elif page == "Profiling Explorer":
    st.title("Profiling Explorer")

    tables = run_query("""
        SELECT DISTINCT DATABASE_NAME || '.' || SCHEMA_NAME || '.' || TABLE_NAME AS TABLE_FQN
        FROM DQ_GUARDIAN.PROFILING.TABLE_PROFILES ORDER BY TABLE_FQN
    """)

    if tables is not None and len(tables) > 0:
        selected = st.selectbox("Select a table", tables["TABLE_FQN"].tolist())
        parts = selected.split(".")

        tp = run_query(f"""
            SELECT ROW_COUNT, COLUMN_COUNT, PROFILED_AT, PROFILE_STATUS
            FROM DQ_GUARDIAN.PROFILING.TABLE_PROFILES
            WHERE DATABASE_NAME = '{parts[0]}' AND SCHEMA_NAME = '{parts[1]}' AND TABLE_NAME = '{parts[2]}'
            ORDER BY PROFILED_AT DESC LIMIT 1
        """)
        if tp is not None and len(tp) > 0:
            r = tp.iloc[0]
            c1, c2, c3 = st.columns(3)
            c1.metric("Rows", int(r["ROW_COUNT"]))
            c2.metric("Columns", int(r["COLUMN_COUNT"]))
            c3.metric("Status", r["PROFILE_STATUS"])

        st.subheader("Column Profiles")
        cp = run_query(f"""
            SELECT COLUMN_NAME, DATA_TYPE, NULL_COUNT, NULL_PCT, DISTINCT_COUNT,
                   MIN_VALUE, MAX_VALUE, MEAN, MEDIAN
            FROM DQ_GUARDIAN.PROFILING.COLUMN_PROFILES
            WHERE DATABASE_NAME = '{parts[0]}' AND SCHEMA_NAME = '{parts[1]}' AND TABLE_NAME = '{parts[2]}'
            ORDER BY PROFILED_AT DESC
        """)
        if cp is not None and len(cp) > 0:
            st.dataframe(cp, use_container_width=True)

        st.subheader("Value Distributions")
        dist = run_query(f"""
            SELECT COLUMN_NAME, VALUE_OR_BUCKET, RECORD_COUNT, PERCENTAGE
            FROM DQ_GUARDIAN.PROFILING.DISTRIBUTION_SNAPSHOTS
            WHERE DATABASE_NAME = '{parts[0]}' AND SCHEMA_NAME = '{parts[1]}' AND TABLE_NAME = '{parts[2]}'
            ORDER BY COLUMN_NAME, RECORD_COUNT DESC
        """)
        if dist is not None and len(dist) > 0:
            dist_col = st.selectbox("Select column", dist["COLUMN_NAME"].unique().tolist())
            filtered = dist[dist["COLUMN_NAME"] == dist_col]
            st.dataframe(filtered, use_container_width=True)
    else:
        st.info("No profiling data available. Run SP_PROFILE_TABLE first.")

# =========================================================
# PAGE 3: CHECK CATALOG
# =========================================================
elif page == "Check Catalog":
    st.title("DQ Check Catalog")

    catalog = run_query("""
        SELECT CHECK_ID, CHECK_NAME, CATEGORY, DESCRIPTION, SEVERITY, WEIGHT,
               CASE WHEN IS_AI_CHECK = TRUE THEN 'Yes' ELSE 'No' END AS AI_ENHANCED,
               CASE WHEN IS_ACTIVE = TRUE THEN 'Active' ELSE 'Inactive' END AS STATUS
        FROM DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY
        ORDER BY CHECK_ID
    """)
    if catalog is not None and len(catalog) > 0:
        st.metric("Total Checks", len(catalog))

        cat_filter = st.selectbox("Filter by category", ["All"] + catalog["CATEGORY"].unique().tolist())
        if cat_filter != "All":
            catalog = catalog[catalog["CATEGORY"] == cat_filter]

        st.dataframe(catalog, use_container_width=True)
    else:
        st.info("No check definitions found.")

# =========================================================
# PAGE 4: RUN HISTORY & RESULTS
# =========================================================
elif page == "Run History & Results":
    st.title("Run History & Results")

    runs = run_query("""
        SELECT RUN_ID, TARGET_TABLE, OVERALL_STATUS, TOTAL_CHECKS,
               PASSED_CHECKS, FAILED_CHECKS, RUN_START_TIME
        FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_RUN_LOG
        ORDER BY RUN_START_TIME DESC LIMIT 50
    """)

    if runs is not None and len(runs) > 0:
        st.subheader("Recent Runs")
        st.dataframe(runs, use_container_width=True)

        run_options = runs.apply(
            lambda r: f"{r['TARGET_TABLE']} | {r['OVERALL_STATUS']} | {str(r['RUN_ID'])[:8]}...",
            axis=1
        ).tolist()
        run_ids = runs["RUN_ID"].tolist()

        selected_idx = st.selectbox("Select a run to inspect", range(len(run_options)),
                                     format_func=lambda i: run_options[i])
        selected_run = run_ids[selected_idx]

        st.subheader("Check Results")
        results = run_query(f"""
            SELECT TARGET_TABLE, CHECK_ID, CHECK_NAME, CHECK_STATUS, SEVERITY, FAILURE_COUNT
            FROM DQ_GUARDIAN.CHECK_RESULTS.V_CHECK_SUMMARY
            WHERE RUN_ID = '{selected_run}'
            ORDER BY CHECK_ID
        """)
        if results is not None and len(results) > 0:
            st.dataframe(results, use_container_width=True)

        st.subheader("Failed Record Samples")
        failed = run_query(f"""
            SELECT CHECK_ID, RECORD_IDENTIFIER, COLUMN_NAME, FAILED_VALUE, FAILURE_REASON
            FROM DQ_GUARDIAN.CHECK_RESULTS.DQ_FAILED_RECORDS
            WHERE RUN_ID = '{selected_run}'
            ORDER BY CHECK_ID LIMIT 50
        """)
        if failed is not None and len(failed) > 0:
            st.dataframe(failed, use_container_width=True)
        else:
            st.info("No failed record samples for this run.")
    else:
        st.info("No DQ runs found. Run SP_RUN_ALL_CHECKS first.")

# =========================================================
# PAGE 5: AI INSIGHTS
# =========================================================
elif page == "AI Insights":
    st.title("AI Insights")

    tab1, tab2 = st.tabs(["Dataset Profiles", "Failure Explanations"])

    with tab1:
        profiles = run_query("""
            SELECT ANALYSIS_ID, TARGET_TABLE, MODEL_USED, STATUS, CREATED_AT,
                   AI_RESPONSE
            FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE
            WHERE ANALYSIS_TYPE = 'PROFILE'
            ORDER BY CREATED_AT DESC
        """)
        if profiles is not None and len(profiles) > 0:
            for _, row in profiles.iterrows():
                with st.expander(f"Profile: {row['TARGET_TABLE']} ({str(row['CREATED_AT'])[:19]})"):
                    st.markdown(row["AI_RESPONSE"])
        else:
            st.info("No AI dataset profiles yet. Run SP_AI_PROFILE_DATASET.")

    with tab2:
        explanations = run_query("""
            SELECT a.ANALYSIS_ID, a.CHECK_ID, a.TARGET_TABLE, a.MODEL_USED,
                   a.CREATED_AT, a.AI_RESPONSE,
                   r.CHECK_NAME, r.CHECK_STATUS, r.SEVERITY
            FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE a
            LEFT JOIN DQ_GUARDIAN.CHECK_RESULTS.DQ_CHECK_RESULTS r
                ON a.RUN_ID = r.RUN_ID AND a.CHECK_ID = r.CHECK_ID
            WHERE a.ANALYSIS_TYPE = 'FAILURE_EXPLANATION'
            ORDER BY a.CREATED_AT DESC
        """)
        if explanations is not None and len(explanations) > 0:
            table_filter = st.selectbox("Filter by table",
                ["All"] + explanations["TARGET_TABLE"].dropna().unique().tolist(),
                key="ai_table_filter")
            if table_filter != "All":
                explanations = explanations[explanations["TARGET_TABLE"] == table_filter]

            for _, row in explanations.iterrows():
                label = f"Check {row['CHECK_ID']}: {row.get('CHECK_NAME', 'N/A')} [{row.get('CHECK_STATUS', '')}]"
                with st.expander(label):
                    st.markdown(row["AI_RESPONSE"])
        else:
            st.info("No failure explanations yet. Run SP_AI_EXPLAIN_FAILURES.")

# =========================================================
# PAGE 6: REMEDIATION CENTER
# =========================================================
elif page == "Remediation Center":
    st.title("Remediation Center")

    tab1, tab2 = st.tabs(["Pending Remediations", "Remediation History"])

    with tab1:
        pending = run_query("""
            SELECT RECOMMENDATION_ID, CHECK_ID, TARGET_TABLE, SAFETY_CLASSIFICATION,
                   RECOMMENDATION_STATUS, APPROVAL_STATUS, ACTION_STATUS, CREATED_AT
            FROM DQ_GUARDIAN.REMEDIATION.V_PENDING_REMEDIATIONS
            ORDER BY CREATED_AT DESC
        """)
        if pending is not None and len(pending) > 0:
            for _, row in pending.iterrows():
                safety = row["SAFETY_CLASSIFICATION"]
                if safety == "SAFE_TO_AUTOMATE":
                    badge = "🟢 SAFE"
                elif safety == "REQUIRES_HUMAN_REVIEW":
                    badge = "🟡 HUMAN REVIEW"
                else:
                    badge = "🔴 " + safety

                with st.expander(f"{badge} | Check {row['CHECK_ID']} | {row['TARGET_TABLE']} | {row['ACTION_STATUS']}"):
                    st.markdown(f"**Safety:** {safety}")
                    st.markdown(f"**Status:** {row['ACTION_STATUS']}")
                    st.markdown(f"**Approval:** {row['APPROVAL_STATUS']}")

                    rec_detail = run_query(f"""
                        SELECT AI_RESPONSE FROM DQ_GUARDIAN.CORTEX_AI.AI_ANALYSIS_CACHE
                        WHERE ANALYSIS_ID = '{row['RECOMMENDATION_ID']}'
                    """)
                    if rec_detail is not None and len(rec_detail) > 0:
                        st.markdown("---")
                        st.markdown(rec_detail.iloc[0]["AI_RESPONSE"])
        else:
            st.info("No pending remediations.")

    with tab2:
        history = run_query("""
            SELECT RECOMMENDATION_ID, CHECK_ID, TARGET_TABLE, SAFETY_CLASSIFICATION,
                   RECOMMENDATION_STATUS, APPROVAL_STATUS, EXECUTION_STATUS,
                   REVIEWER, EXECUTED_AT, CREATED_AT
            FROM DQ_GUARDIAN.REMEDIATION.V_REMEDIATION_HISTORY
            ORDER BY CREATED_AT DESC
        """)
        if history is not None and len(history) > 0:
            st.dataframe(history, use_container_width=True)
        else:
            st.info("No remediation history yet.")

# =========================================================
# PAGE 7: NATURAL LANGUAGE QUERY
# =========================================================
elif page == "Natural Language Query":
    st.title("Natural Language Query")
    st.markdown("Ask a business question about your data quality in plain English.")

    question = st.text_input("Enter your question:", placeholder="e.g., Which tables have the most failures?")

    if st.button("Ask", disabled=not question):
        with st.spinner("Analyzing your question with Cortex AI..."):
            escaped = question.replace("'", "''")
            result = run_query(f"CALL DQ_GUARDIAN.CORTEX_AI.SP_AI_NATURAL_LANGUAGE_QUERY('{escaped}')")

            if result is not None and len(result) > 0:
                import json
                raw = result.iloc[0, 0]
                try:
                    resp = json.loads(raw) if isinstance(raw, str) else raw
                except:
                    st.error("Could not parse procedure response.")
                    st.code(str(raw))
                    resp = None

                if resp:
                    status = resp.get("status", "UNKNOWN")

                    if status == "SUCCESS":
                        st.success(f"Query executed successfully. {resp.get('row_count', 0)} row(s) returned.")

                        st.markdown("**AI-Generated SQL:**")
                        st.code(resp.get("generated_sql", ""), language="sql")

                        rows = resp.get("rows", [])
                        if rows:
                            import pandas as pd
                            df = pd.DataFrame(rows)
                            st.dataframe(df, use_container_width=True)
                        else:
                            st.info("The query returned no rows.")

                    elif status == "BLOCKED":
                        st.error("Query blocked by safety validation.")
                        st.markdown(f"**Reason:** {resp.get('message', '')}")
                        if resp.get("generated_sql"):
                            st.markdown("**AI-Generated SQL (blocked):**")
                            st.code(resp.get("generated_sql", ""), language="sql")

                    elif status == "EXECUTION_ERROR":
                        st.error("Generated SQL failed to execute.")
                        st.markdown(f"**Error:** {resp.get('message', '')}")
                        if resp.get("generated_sql"):
                            st.markdown("**AI-Generated SQL:**")
                            st.code(resp.get("generated_sql", ""), language="sql")

                    else:
                        st.warning(f"Status: {status}")
                        st.markdown(f"**Message:** {resp.get('message', '')}")
            else:
                st.error("No response from the procedure.")

# =========================================================
# PAGE 8: CONFIGURATION
# =========================================================
elif page == "Configuration":
    st.title("Configuration Settings")

    st.subheader("Monitored Tables")
    tables = run_query("""
        SELECT DISTINCT TARGET_DATABASE, TARGET_SCHEMA, TARGET_TABLE
        FROM DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS
        WHERE IS_ACTIVE = TRUE
        ORDER BY TARGET_TABLE
    """)
    if tables is not None:
        st.dataframe(tables, use_container_width=True)

    st.subheader("Active Check Assignments")
    assignments = run_query("""
        SELECT a.CHECK_ID, l.CHECK_NAME, a.TARGET_TABLE, a.TARGET_COLUMN, l.SEVERITY
        FROM DQ_GUARDIAN.CONFIG.DQ_CHECK_ASSIGNMENTS a
        JOIN DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY l ON a.CHECK_ID = l.CHECK_ID
        WHERE a.IS_ACTIVE = TRUE
        ORDER BY a.TARGET_TABLE, a.CHECK_ID
    """)
    if assignments is not None:
        st.metric("Total Active Assignments", len(assignments))
        st.dataframe(assignments, use_container_width=True)

    st.subheader("Thresholds")
    thresholds = run_query("""
        SELECT t.CHECK_ID, l.CHECK_NAME, t.TARGET_TABLE,
               t.WARNING_THRESHOLD, t.FAIL_THRESHOLD
        FROM DQ_GUARDIAN.CONFIG.DQ_THRESHOLDS t
        JOIN DQ_GUARDIAN.CONFIG.DQ_CHECK_LIBRARY l ON t.CHECK_ID = l.CHECK_ID
        ORDER BY t.TARGET_TABLE, t.CHECK_ID
    """)
    if thresholds is not None:
        st.dataframe(thresholds, use_container_width=True)

    st.subheader("Scheduled Tasks")
    tasks = run_query("""
        SELECT name AS TASK_NAME, state AS STATUS, schedule AS SCHEDULE, warehouse AS WAREHOUSE
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    """)
    st.info("Tasks are currently SUSPENDED. Use SYSTEM$TASK_DEPENDENTS_ENABLE to activate.")
    tasks_df = run_query("SHOW TASKS IN SCHEMA DQ_GUARDIAN.CONFIG")
    if tasks_df is not None and len(tasks_df) > 0:
        st.dataframe(tasks_df[["name", "state", "schedule", "warehouse"]], use_container_width=True)
