-- 06_insights.sql
-- Customer churn analysis - insight queries (MySQL 8)
-- Run after 04_views.sql. All read v_churn_enriched.
--
-- 05_analysis.sql describes where churn rates differ. These queries test
-- whether those differences are decision-relevant: how much of all churn
-- each segment accounts for, whether patterns survive like-with-like
-- comparison, and where the data contradicts an easy story. They still read
-- a snapshot: tenure is recorded at churn for those who left and at the
-- snapshot date for those who stayed, and no result here is causal proof.

USE churn_analysis;

-- I1. Contribution vs rate, by contract.
-- A segment can have a high churn rate and matter little (small), or a
-- lower rate and matter a lot (big). This shows both: share of the customer
-- base, share of all churned customers, churn rate, and share of the
-- monthly revenue that churned customers were paying.
SELECT
    Contract,
    COUNT(*)                                                AS customers,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM v_churn_enriched), 1)          AS pct_of_customers,
    SUM(Churn = 'Yes')                                      AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / (SELECT COUNT(*) FROM v_churn_enriched WHERE Churn = 'Yes'), 1) AS pct_of_all_churn,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)         AS churn_pct,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges END), 2)           AS churned_monthly_revenue,
    ROUND(100.0 * SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges END)
        / (SELECT SUM(MonthlyCharges) FROM v_churn_enriched WHERE Churn = 'Yes'), 1) AS pct_of_churned_revenue
FROM v_churn_enriched
GROUP BY Contract
ORDER BY churned DESC;

-- I2. The priority segment: month-to-month customers with recorded tenure
-- 0-12 months. How much of the whole problem sits there?
SELECT
    CASE WHEN Contract = 'Month-to-month' AND tenure <= 12
         THEN 'Month-to-month, tenure 0-12' ELSE 'Everyone else' END AS segment,
    COUNT(*)                                                AS customers,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM v_churn_enriched), 1)          AS pct_of_customers,
    SUM(Churn = 'Yes')                                      AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / (SELECT COUNT(*) FROM v_churn_enriched WHERE Churn = 'Yes'), 1) AS pct_of_all_churn,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)         AS churn_pct,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges END), 2)           AS churned_monthly_revenue
FROM v_churn_enriched
GROUP BY segment
ORDER BY segment DESC;

-- I3. Confounding check, direction 1: contract within tenure bands.
-- If month-to-month churned more only because such customers are newer,
-- the gap would vanish inside a tenure band. It does not.
-- Caveat: contract choice is self-selected, so a surviving gap is still an
-- association, not proof that the contract itself retains anyone.
SELECT
    tenure_band,
    Contract,
    COUNT(*)                                                AS customers,
    SUM(Churn = 'Yes')                                      AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)         AS churn_pct
FROM v_churn_enriched
GROUP BY tenure_band, Contract
ORDER BY tenure_band, churn_pct DESC;

-- I4. Confounding check, direction 2: payment method within one contract.
-- Electronic-check payers churn most overall (45.3%), but they also skew
-- toward month-to-month (see I5). Inside month-to-month alone, the
-- electronic-check gap shrinks but remains.
SELECT
    PaymentMethod,
    COUNT(*)                                                AS customers,
    SUM(Churn = 'Yes')                                      AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)         AS churn_pct
FROM v_churn_enriched
WHERE Contract = 'Month-to-month'
GROUP BY PaymentMethod
ORDER BY churn_pct DESC;

-- I5. Payment-method mix by contract - how much of the electronic-check
-- pattern is simply that such payers choose month-to-month more often.
SELECT
    Contract,
    COUNT(*)                                                AS customers,
    SUM(PaymentMethod = 'Electronic check')                 AS echeck_customers,
    ROUND(100.0 * SUM(PaymentMethod = 'Electronic check') / COUNT(*), 1) AS echeck_pct
FROM v_churn_enriched
GROUP BY Contract
ORDER BY echeck_pct DESC;

-- I6. Fiber optic: is it the price? Fiber customers churn far more than DSL
-- (41.9% vs 19.0%) and pay far more on average ($91.5 vs $58.1). If price
-- were the whole story, churn should rise with price inside fiber. It does
-- not - the most expensive fiber tier churns least. A simple
-- higher-bill-means-higher-churn narrative is not supported here, and
-- causal price effects are not identified; treat the fiber gap as
-- unexplained.
SELECT
    InternetService,
    COUNT(*)                                                AS customers,
    ROUND(AVG(MonthlyCharges), 2)                           AS avg_monthly_charges,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)         AS churn_pct
FROM v_churn_enriched
WHERE InternetService <> 'No'
GROUP BY InternetService;

SELECT
    CASE WHEN MonthlyCharges < 70  THEN 'under $70'
         WHEN MonthlyCharges < 90  THEN '$70-90'
         WHEN MonthlyCharges < 100 THEN '$90-100'
         ELSE '$100+' END                                   AS price_tier,
    COUNT(*)                                                AS customers,
    SUM(Churn = 'Yes')                                      AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)         AS churn_pct
FROM v_churn_enriched
WHERE InternetService = 'Fiber optic'
GROUP BY price_tier
ORDER BY price_tier;

-- I7. Tech support inside the priority segment. Among month-to-month
-- customers with recorded tenure 0-12 months, churn is higher without tech
-- support - but the with-support group is small (check the counts), so read
-- this as a lead, not a conclusion. 'No internet service' customers have no
-- support plan to speak of and are shown separately.
SELECT
    TechSupport,
    COUNT(*)                                                AS customers,
    SUM(Churn = 'Yes')                                      AS churned,
    ROUND(100.0 * SUM(Churn = 'Yes') / COUNT(*), 1)         AS churn_pct
FROM v_churn_enriched
WHERE Contract = 'Month-to-month' AND tenure <= 12
GROUP BY TechSupport
ORDER BY churn_pct DESC;


-- I8. Pareto view: which segments carry the churn?
-- Systematic scan of contract x internet service x tech support, restricted
-- to segments of 100+ customers so tiny cells cannot dominate. The running
-- column (a window function) shows how quickly the concentration adds up:
-- the top segment alone holds over half of all churn in this sample.
SELECT
    CONCAT(Contract, ' / ', InternetService, ' / ',
           CASE TechSupport WHEN 'Yes' THEN 'support'
                            WHEN 'No'  THEN 'no-support'
                            ELSE 'no-internet' END)        AS segment,
    COUNT(*)                                                AS customers,
    SUM(churned)                                            AS churned,
    ROUND(100.0 * SUM(churned) / COUNT(*), 1)               AS churn_pct,
    ROUND(100.0 * SUM(churned)
        / (SELECT SUM(churned) FROM v_churn_enriched), 1)   AS pct_of_all_churn,
    ROUND(100.0 * SUM(SUM(churned)) OVER (ORDER BY SUM(churned) DESC
            ROWS UNBOUNDED PRECEDING)
        / (SELECT SUM(churned) FROM v_churn_enriched), 1)   AS cumulative_pct_of_churn
FROM v_churn_enriched
GROUP BY segment
HAVING customers >= 100
ORDER BY churned DESC;

-- I9. Price deciles: is churn simply "expensive customers leave"?
-- NTILE(10) splits the base into ten equal groups by monthly bill. Churn
-- rises through the middle deciles, peaks at decile 9 (40.9%), then DROPS
-- at the most expensive decile (24.7%). The relationship is not monotonic,
-- so a simple "higher bill means higher churn" narrative is not supported
-- by these comparisons - consistent with the within-fiber result in I6.
-- Causal price effects are not identified in this observational snapshot.
SELECT
    decile,
    COUNT(*)                                                AS customers,
    ROUND(MIN(MonthlyCharges), 2)                           AS min_bill,
    ROUND(MAX(MonthlyCharges), 2)                           AS max_bill,
    SUM(churned)                                            AS churned,
    ROUND(100.0 * SUM(churned) / COUNT(*), 1)               AS churn_pct
FROM (
    SELECT MonthlyCharges, churned,
           NTILE(10) OVER (ORDER BY MonthlyCharges) AS decile
    FROM v_churn_enriched
) d
GROUP BY decile
ORDER BY decile;

-- I10. The add-on ladder: churn by count of optional services held.
-- Read carefully: the 0-add-on row (21.4%) is a MIX - it contains the
-- 1,526 no-internet customers (7.4% churn), who structurally cannot hold
-- add-ons, alongside internet customers who simply hold none. From 1
-- add-on upward the gradient is monotonic (45.8% down to 5.3%), and
-- inside fiber specifically it is monotonic across every step (60.4%
-- down to 9.2%) with no mix problem. Caveat: customers choose add-ons,
-- so engaged customers self-select. The fiber ladder is the clean
-- engagement signal; the overall ladder shows why denominators matter.
SELECT
    addon_count,
    COUNT(*)                                                AS customers,
    SUM(churned)                                            AS churned,
    ROUND(100.0 * SUM(churned) / COUNT(*), 1)               AS churn_pct
FROM v_churn_enriched
GROUP BY addon_count
ORDER BY addon_count;

SELECT
    addon_count,
    COUNT(*)                                                AS customers,
    SUM(churned)                                            AS churned,
    ROUND(100.0 * SUM(churned) / COUNT(*), 1)               AS churn_pct
FROM v_churn_enriched
WHERE InternetService = 'Fiber optic'
GROUP BY addon_count
ORDER BY addon_count;

-- I11. Robustness check: medians confirm the averages. MySQL 8 has no
-- PERCENTILE_CONT, so the median is computed explicitly with ROW_NUMBER:
-- middle row (or average of the two middle rows) per group.
SELECT
    Churn,
    COUNT(*)                                                AS customers,
    ROUND(AVG(MonthlyCharges), 2)                           AS median_monthly_charges
FROM (
    SELECT Churn, MonthlyCharges,
           ROW_NUMBER() OVER (PARTITION BY Churn ORDER BY MonthlyCharges) AS rn,
           COUNT(*)     OVER (PARTITION BY Churn) AS n
    FROM v_churn_enriched
) ranked
WHERE rn IN ((n + 1) DIV 2, (n + 2) DIV 2)
GROUP BY Churn;
