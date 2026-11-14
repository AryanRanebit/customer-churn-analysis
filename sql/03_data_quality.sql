-- 03_data_quality.sql
-- Customer churn analysis - data quality battery (MySQL 8)
-- Run after 02_model.sql, against churn_analysis.
--
-- Every check is a row of output: what was checked, what was expected, what
-- was found, and PASS or REVIEW. "REVIEW" does not mean the data is broken;
-- it marks results a reader should look at and understand before trusting
-- the analysis (explained in the README). No table is modified here; the
-- battery only reads.

USE churn_analysis;

-- Structural checks on the staged raw table.
SELECT 'row count' AS check_name, '7043' AS expected,
       CAST(COUNT(*) AS CHAR) AS actual,
       IF(COUNT(*) = 7043, 'PASS', 'FAIL') AS status
FROM telco_churn
UNION ALL
SELECT 'customerID unique', '0 duplicates',
       CAST(COUNT(*) AS CHAR),
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM (SELECT customerID FROM telco_churn GROUP BY customerID HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'churn labels in {Yes,No}', '0 outside',
       CAST(COUNT(*) AS CHAR),
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM telco_churn WHERE Churn NOT IN ('Yes', 'No')
UNION ALL
SELECT 'tenure in 0-72', '0 outside',
       CAST(COUNT(*) AS CHAR),
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM telco_churn WHERE tenure < 0 OR tenure > 72
UNION ALL
SELECT 'MonthlyCharges in (0, 1000)', '0 outside',
       CAST(COUNT(*) AS CHAR),
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM telco_churn WHERE MonthlyCharges <= 0 OR MonthlyCharges >= 1000
UNION ALL
SELECT 'TotalCharges NULL only at recorded tenure 0', '11 rows, all tenure 0',
       CAST(SUM(TotalCharges IS NULL) AS CHAR),
       IF(SUM(TotalCharges IS NULL) = 11
          AND SUM(TotalCharges IS NULL AND tenure <> 0) = 0
          AND SUM(tenure = 0 AND TotalCharges IS NOT NULL) = 0,
          'PASS', 'FAIL')
FROM telco_churn
UNION ALL
SELECT 'TotalCharges >= MonthlyCharges when tenure >= 1', '0 violations',
       CAST(COUNT(*) AS CHAR),
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM telco_churn WHERE tenure >= 1 AND TotalCharges < MonthlyCharges
UNION ALL
-- TotalCharges is not exactly MonthlyCharges x tenure for most customers:
-- 731 match within $1 (614 exactly, 613 of those at tenure 1, where
-- equality is forced), and 2,323 deviate by $50 or more - almost all of
-- them long-tenured (89 rows at recorded tenure 0-12 vs 1,254 at 49+).
-- One plausible explanation is price changes over a customer's life, but
-- this data does not establish the cause. REVIEW is the honest status:
-- understood, not clean.
SELECT 'TotalCharges tracks MonthlyCharges x tenure',
       'explained pattern',
       CONCAT(SUM(ABS(TotalCharges - MonthlyCharges * tenure) < 1), ' exact / ',
              SUM(ABS(TotalCharges - MonthlyCharges * tenure) >= 50), ' deviate >= $50'),
       'REVIEW'
FROM telco_churn WHERE tenure > 0 AND TotalCharges IS NOT NULL
UNION ALL
SELECT 'gender mix', 'roughly balanced',
       CONCAT(SUM(gender = 'Female'), ' F / ', SUM(gender = 'Male'), ' M'),
       'REVIEW'
FROM telco_churn
UNION ALL
-- Referential integrity of the normalized model: every services and billing
-- row must join back to exactly one customer, and vice versa.
SELECT 'model: services without customer', '0',
       CAST(COUNT(*) AS CHAR),
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM customer_services s LEFT JOIN customers c ON c.customerID = s.customerID
WHERE c.customerID IS NULL
UNION ALL
SELECT 'model: billing without customer', '0',
       CAST(COUNT(*) AS CHAR),
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM customer_billing b LEFT JOIN customers c ON c.customerID = b.customerID
WHERE c.customerID IS NULL
UNION ALL
SELECT 'model: customers without billing', '0',
       CAST(COUNT(*) AS CHAR),
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM customers c LEFT JOIN customer_billing b ON b.customerID = c.customerID
WHERE b.customerID IS NULL
ORDER BY check_name;
