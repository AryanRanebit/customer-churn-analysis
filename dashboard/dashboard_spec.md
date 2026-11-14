# Dashboard spec: churn analysis

The interactive layer over the SQL work. Everything shown is an observed
snapshot metric from `v_churn_enriched` - no projections, no fabricated
revenue impact, no causal claims. The data export is
`dashboard/churn_dashboard_dataset.csv` (7,043 rows, one per customer,
exported from the MySQL view; `TotalCharges` empty for the 11
recorded-tenure-0 customers).

## Dataset fields

| Field | Type | Notes |
| --- | --- | --- |
| customerID | text | unique key |
| gender, Partner, Dependents, PaperlessBilling | text | Yes/No demographics |
| SeniorCitizen | 0/1 | flag |
| tenure | int | months recorded at snapshot/churn |
| tenure_band | text | 0-12 / 13-24 / 25-48 / 49+ (from the view) |
| Contract | text | Month-to-month / One year / Two year |
| PhoneService, MultipleLines, InternetService | text | services |
| OnlineSecurity, OnlineBackup, DeviceProtection, TechSupport, StreamingTV, StreamingMovies | text | optional add-ons |
| addon_count | int | 0-6, count of add-ons held |
| PaymentMethod | text | incl. Electronic check |
| MonthlyCharges | decimal | current monthly bill |
| TotalCharges | decimal, nullable | billed total; 11 blanks at tenure 0 |
| Churn | text | Yes/No label |
| churned | 0/1 | numeric flag for rate measures |

## Measures (tool-agnostic definitions)

- **Customers** = COUNT(customerID) → 7,043
- **Churned customers** = SUM(churned) → 1,869
- **Churn rate** = SUM(churned) / COUNT(customerID) → 26.5% (format as %)
- **Churned monthly revenue** = SUM(MonthlyCharges where churned = 1) →
  $139,130.85. Label it "monthly bills of churned customers (sample)",
  never "revenue lost" or "revenue saved".
- **Avg monthly bill** = AVG(MonthlyCharges) → $61.27 stayed / $74.44 churned
- **Median monthly bill** → $64.43 stayed / $79.65 churned (MEDIAN if the
  tool has it; otherwise precomputed)

## Pages and visuals

**Page 1 - Overview.** KPI cards: Customers, Churned customers, Churn rate,
Churned monthly revenue. Bar: churn rate by Contract (42.7 / 11.3 / 2.8).
Bar: churn rate by tenure_band (47.4 / 28.7 / 20.4 / 9.5).
Slicers (page filters): Contract, InternetService, TechSupport,
tenure_band, PaymentMethod, addon_count.

**Page 2 - Drivers.** Bar: churn rate by monthly bill band (CASE bins over
MonthlyCharges, all ties at a boundary land in the lower band): 8.51 /
9.82 / 25.47 / 24.43 / 21.58 / 38.14 / 37.87 / 34.33 / 40.91 / 24.72.
Note on binning definitions: sql/06_insights.sql I9 uses NTILE(10)
equal-count deciles (ties split arbitrarily), giving 8.7 / 9.4 / 25.5 /
24.4 / 21.7 / 37.9 / 37.9 / 34.2 / 40.9 / 24.7 (recorded in
analysis/results.json). The two series answer slightly different questions
and differ mainly at tie-heavy bill values (e.g. the $20.05 boundary):
equal-count deciles split a tie group across two deciles, while CASE bands
keep every tie in one band, so a different engine's tie order can also
shift a few rows between adjacent deciles. Both are correct - the
dashboard labels its chart "bill band", the SQL labels its query
deciles. Bar: churn rate by addon_count, filtered
to fiber (60.4 down to 9.2). Table: contract x internet x support Pareto
(top segment 55.3% of all churn, top 3 = 79.1%). Bar: churn rate by
PaymentMethod (45.3 / 19.1 / 16.7 / 15.2).

**Page 3 - Model results.** Table of measured scores (baseline 73.5% /
0.500 AUC; logistic regression 78.9% / 0.832; decision tree 78.1% / 0.819;
random forest 78.5% / 0.832; selected on validation, test reported for
all). Confusion matrix as a small table (914 / 121 / 177 / 197). Feature
importance chart from `analysis/figures/feature_importance.png` (image) or
a bar of the top 8. Caption: retrospective sample-data model, not
deployment-ready.

## Caveat block (on page 1, small text)

Fictional IBM sample, one snapshot in time. Associations, not causes.
Tenure is recorded at churn for leavers and at the snapshot date for
stayers. Model scores are retrospective; a deployment would need
point-in-time features.
