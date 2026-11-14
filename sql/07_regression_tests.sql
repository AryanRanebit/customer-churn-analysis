-- 07_regression_tests.sql
-- Customer churn analysis - regression tests (MySQL 8)
-- Run after 04_views.sql, against churn_analysis.
--
-- Two jobs:
--   1. Recompute the headline numbers from the staged raw table and compare
--      them against the values the README reports. If someone edits a
--      query, swaps the CSV, or changes the model, this battery shows
--      exactly which number moved.
--   2. Prove the normalized model + view reproduce the staged raw table
--      (row counts and key sums must match exactly).
-- The final statement is a gate: it raises ERROR 3141 if any check failed,
-- so a broken run cannot be mistaken for a green one - the same deliberate
-- failure technique as the setup gate in 01_setup.sql.
--
-- The battery is materialized into a session-scoped TEMPORARY table so the
-- displayed results and the gate read the exact same rows - one battery,
-- no second copy to drift out of sync.

USE churn_analysis;

DROP TEMPORARY TABLE IF EXISTS tmp_churn_regression;

CREATE TEMPORARY TABLE tmp_churn_regression AS
WITH checks AS (
    SELECT 'rows' AS test, '7043' AS expected,
           CAST((SELECT COUNT(*) FROM telco_churn) AS CHAR) AS actual
    UNION ALL
    SELECT 'churned', '1869',
           CAST((SELECT COUNT(*) FROM telco_churn WHERE Churn = 'Yes') AS CHAR)
    UNION ALL
    SELECT 'overall churn_pct', '26.5',
           CAST(ROUND(100.0 * (SELECT COUNT(*) FROM telco_churn WHERE Churn = 'Yes')
                      / (SELECT COUNT(*) FROM telco_churn), 1) AS CHAR)
    UNION ALL
    SELECT 'month-to-month churn_pct', '42.7',
           CAST(ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1) AS CHAR)
           FROM telco_churn WHERE Contract = 'Month-to-month'
    UNION ALL
    SELECT 'two-year churn_pct', '2.8',
           CAST(ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1) AS CHAR)
           FROM telco_churn WHERE Contract = 'Two year'
    UNION ALL
    SELECT 'priority segment churn_pct', '51.4',
           CAST(ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1) AS CHAR)
           FROM telco_churn WHERE Contract = 'Month-to-month' AND tenure <= 12
    UNION ALL
    SELECT 'churned monthly revenue', '139130.85',
           CAST(ROUND(SUM(MonthlyCharges), 2) AS CHAR)
           FROM telco_churn WHERE Churn = 'Yes'
    UNION ALL
    SELECT 'NULL TotalCharges', '11',
           CAST((SELECT COUNT(*) FROM telco_churn WHERE TotalCharges IS NULL) AS CHAR)
    UNION ALL
    -- Model reconciliation: the view over the 3-table model must reproduce raw.
    SELECT 'model: view rows = raw rows', '7043',
           CAST((SELECT COUNT(*) FROM v_churn_enriched) AS CHAR)
    UNION ALL
    SELECT 'model: view churned = raw churned', '1869',
           CAST((SELECT SUM(churned) FROM v_churn_enriched) AS CHAR)
    UNION ALL
    SELECT 'model: view monthly revenue = raw', '456116.60',
           CAST((SELECT ROUND(SUM(MonthlyCharges), 2) FROM v_churn_enriched) AS CHAR)
    UNION ALL
    SELECT 'model: view total revenue = raw', '16056168.70',
           CAST((SELECT ROUND(SUM(TotalCharges), 2) FROM v_churn_enriched) AS CHAR)
    UNION ALL
    SELECT 'model: view NULL TotalCharges = raw', '11',
           CAST((SELECT COUNT(*) FROM v_churn_enriched WHERE TotalCharges IS NULL) AS CHAR)
)
SELECT test, expected, actual, IF(expected = actual, 'PASS', 'FAIL') AS status
FROM checks;

SELECT * FROM tmp_churn_regression ORDER BY test;

-- Gate: any FAIL above aborts here with an error instead of passing quietly.
SELECT CASE
         WHEN (SELECT COUNT(*) FROM tmp_churn_regression WHERE status = 'FAIL') = 0
         THEN 'ALL TESTS PASSED'
         ELSE JSON_EXTRACT('deliberately invalid JSON: a regression test failed - read the table above', '$')
       END AS regression_gate;
