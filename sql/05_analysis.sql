-- 05_analysis.sql
-- Customer churn analysis - descriptive queries (MySQL 8)
-- Run after 04_views.sql. Each query answers one business question; all read
-- the v_churn_enriched view over the normalized model. Findings and numbers
-- are in the README; the same numbers are reproduced from the staged raw
-- table by 07_regression_tests.sql.

USE churn_analysis;

-- Q1. Overall churn: how many customers left, out of how many?
SELECT
    COUNT(*)                                          AS customers,
    SUM(Churn = 'Yes')                                AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)   AS churn_pct
FROM v_churn_enriched;

-- Q2. Does churn differ by contract type?
SELECT
    Contract,
    COUNT(*)                                          AS customers,
    SUM(Churn = 'Yes')                                AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)   AS churn_pct
FROM v_churn_enriched
GROUP BY Contract
ORDER BY churn_pct DESC;

-- Q3. Does churn differ by how long the customer has been with the company?
-- tenure_band comes from the view so every query buckets tenure identically.
SELECT
    tenure_band,
    COUNT(*)                                          AS customers,
    SUM(Churn = 'Yes')                                AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)   AS churn_pct
FROM v_churn_enriched
GROUP BY tenure_band
ORDER BY MIN(tenure);

-- Q4. Does the internet service type matter?
SELECT
    InternetService,
    COUNT(*)                                          AS customers,
    SUM(Churn = 'Yes')                                AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)   AS churn_pct
FROM v_churn_enriched
GROUP BY InternetService
ORDER BY churn_pct DESC;

-- Q5. Does the payment method matter?
SELECT
    PaymentMethod,
    COUNT(*)                                          AS customers,
    SUM(Churn = 'Yes')                                AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)   AS churn_pct
FROM v_churn_enriched
GROUP BY PaymentMethod
ORDER BY churn_pct DESC;

-- Q6. Do churned customers pay more per month?
SELECT
    Churn,
    COUNT(*)                       AS customers,
    ROUND(AVG(MonthlyCharges), 2)  AS avg_monthly_charges,
    ROUND(AVG(tenure), 1)          AS avg_tenure_months
FROM v_churn_enriched
GROUP BY Churn;

-- Q7. Do customers with tech support or online security stay longer?
SELECT
    TechSupport,
    COUNT(*)                                          AS customers,
    SUM(Churn = 'Yes')                                AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)   AS churn_pct
FROM v_churn_enriched
GROUP BY TechSupport
ORDER BY churn_pct DESC;

-- Q8. A combined segment: month-to-month AND recorded tenure 0-12 months.
-- This is a snapshot of who left, not a prediction of who will leave.
SELECT
    CASE
        WHEN Contract = 'Month-to-month' AND tenure <= 12
            THEN 'Month-to-month, tenure 0-12'
        ELSE 'Everyone else'
    END                                               AS segment,
    COUNT(*)                                          AS customers,
    SUM(Churn = 'Yes')                                AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)   AS churn_pct
FROM v_churn_enriched
GROUP BY segment;

-- Q9. Monthly revenue tied to customers who left (sample scale, for context).
SELECT
    ROUND(SUM(MonthlyCharges), 2)  AS monthly_revenue_from_churned,
    COUNT(*)                       AS churned_customers
FROM v_churn_enriched
WHERE Churn = 'Yes';
