-- 04_views.sql
-- Customer churn analysis - analysis view (MySQL 8)
-- Run after 02_model.sql, against churn_analysis.
--
-- One view the analysis reads: the three model tables joined back to one
-- row per customer, plus the derived fields the analysis uses repeatedly
-- (churn flag, tenure band, add-on count). Deriving once, in one reviewed
-- place, keeps every downstream query on the same definitions.
--
-- Plain CREATE VIEW, matching this project's fail-closed rule: if any
-- object named v_churn_enriched already exists (including one that is not
-- ours), the statement errors and changes nothing. To rebuild the view
-- deliberately, drop it yourself first - that choice stays with you, not
-- the script.
--
-- 07_regression_tests.sql reconciles this view against the staged raw
-- table, so a modelling mistake cannot silently change the analysis.

USE churn_analysis;

CREATE VIEW v_churn_enriched AS
SELECT
    c.customerID,
    c.gender,
    c.SeniorCitizen,
    c.Partner,
    c.Dependents,
    c.tenure,
    CASE WHEN c.tenure <= 12 THEN '0-12'
         WHEN c.tenure <= 24 THEN '13-24'
         WHEN c.tenure <= 48 THEN '25-48'
         ELSE '49+' END                                  AS tenure_band,
    c.Contract,
    c.PaperlessBilling,
    s.PhoneService,
    s.MultipleLines,
    s.InternetService,
    s.OnlineSecurity,
    s.OnlineBackup,
    s.DeviceProtection,
    s.TechSupport,
    s.StreamingTV,
    s.StreamingMovies,
    -- Number of optional add-on services the customer holds (0-6).
    (s.OnlineSecurity = 'Yes') + (s.OnlineBackup = 'Yes')
  + (s.DeviceProtection = 'Yes') + (s.TechSupport = 'Yes')
  + (s.StreamingTV = 'Yes') + (s.StreamingMovies = 'Yes') AS addon_count,
    b.PaymentMethod,
    b.MonthlyCharges,
    b.TotalCharges,
    c.Churn,
    (c.Churn = 'Yes')                                     AS churned
FROM customers c
JOIN customer_services s ON s.customerID = c.customerID
JOIN customer_billing  b ON b.customerID = c.customerID;
