# Interview walkthrough: how to explain this project

This document exists so the project can be *defended*, not just shown. Every
claim below is already verified by the SQL regression battery
(`sql/07_regression_tests.sql`) or the Python test suite
(`analysis/tests/`), so nothing here is a number you would have to walk back
mid-interview.

## The 60-second version

> I took a raw telecom churn CSV of 7,043 customers and built the full path
> from file to answer. On the SQL side: a fail-safe import that can't
> overwrite anything, a normalized three-table model, a 12-check data-quality
> battery, and insight queries using window functions, all protected by a
> 13-check regression battery that hard-fails if any headline number moves.
> The findings: churn is 26.5% overall but concentrated - month-to-month
> customers are 55.0% of the base and 88.6% of churners, and one segment
> (month-to-month, fiber, no tech support) holds 55.3% of all churned
> customers. On the Python side I checked whether those signals predict
> churn: three leak-safe sklearn pipelines compared against a majority
> baseline on a stratified 60/20/20 split, selected on validation ROC-AUC.
> Logistic regression won (0.832 test AUC vs 0.500 baseline), but every
> model misses about half the churners, which is itself a finding: a
> snapshot can't see behavior. So the project ends in an experiment design,
> not a deployed score.

## Architecture tour (what to say when they open a file)

| File | What it does | The point to make |
| --- | --- | --- |
| `sql/01_setup.sql` | Loads the CSV into a session-private TEMPORARY staging table, validates shape (7,043 rows, unique IDs, Yes/No labels, 11 NULL TotalCharges), then a gated CREATE TABLE | "A bad file fails loudly and creates nothing - no half-made tables. The gate uses SIGNAL, so even `--force` can't skip it." |
| `sql/02_model.sql` | Splits the wide row into customers / customer_services / customer_billing | "Real churn data lives in CRM, product and billing systems; I modeled that shape instead of analyzing one flat file." |
| `sql/03_data_quality.sql` | 12 checks with PASS / REVIEW statuses | "REVIEW means understood, not clean - I'd rather flag a caveat than hide it." |
| `sql/04_views.sql` | `v_churn_enriched`: tenure banding, churn flag, add-on count defined once | "One definition of each derived field, not a copy in every query." |
| `sql/05_analysis.sql`, `sql/06_insights.sql` | Descriptive and insight queries (NTILE deciles, ROW_NUMBER median, running cumulative share) | The findings below. |
| `sql/07_regression_tests.sql` | 13 checks recompute headline numbers from staged raw and hard-fail on drift | "Every number in the README is restated as an expected constant. Edit anything and the battery shows which number moved." |
| `analysis/run_analysis.py` | Re-runs the same logic on SQLite as a second engine | "Two engines agreeing is cheap insurance against dialect bugs." |
| `analysis/tests/` | Python regression suite: CSV shape, query outputs vs committed JSON, model-result invariants, end-to-end model reproduction | "The Python layer has the same drift protection as the SQL layer." |
| `analysis/run_churn_model.py` | Three sklearn pipelines vs a majority baseline | The modeling story below. |
| `docs/experiment.md` | A/B test design for contract conversion | "Associations earn a test, not a decision - so I designed the test." |
| `dashboard/` | Looker Studio extract + full spec with expected values | "The BI layer reads the same view, and its spec records the one place it legitimately differs from the SQL (fixed bill bands vs NTILE deciles)." |

## Questions interviewers actually ask

**"Why normalize a single flat file?"**
Because the wide row mixes three kinds of facts: identity, subscribed
services, and billing. Real systems store those separately, so the project
models that shape and joins it back through one view. The regression battery
proves the model reproduces the staged raw table exactly - row counts, churn
counts, revenue sums, NULL pattern - so the normalization can't silently
lose or duplicate anyone.

**"Why no foreign keys?"**
MySQL 8 forbids FK constraints in `CREATE TABLE ... AS SELECT` (ERROR 3978),
and the project's rule is create-only, never ALTER. The relationships are
verified instead by anti-join checks in the data-quality battery. For an
analytics schema rebuilt from a validated source, that's the right trade -
and it's a documented, deliberate one.

**"Tell me about a window function you used."**
Three good ones to pick from:
- `NTILE(10)` over MonthlyCharges splits the base into price deciles (I9).
  Churn rises from 8.7% and 9.4% at the bottom to a 40.9% peak at decile 9,
  then *drops* to 24.7% at the most expensive decile - which is why the
  project rejects a simple "higher bill, higher churn" story.
- `ROW_NUMBER() OVER (PARTITION BY Churn ORDER BY MonthlyCharges)` with a
  `COUNT(*) OVER` picks the middle row(s) for a median in MySQL, which has
  no MEDIAN(): churned customers' median bill is $79.65 vs $64.43 for
  stayers (I11).
- `SUM(...) OVER (ORDER BY ... ROWS UNBOUNDED PRECEDING)` gives the running
  cumulative share in the segment scan (I8), showing the top three
  100+-customer segments hold 79.1% of all churned customers.

**"How do you know your import is safe?"**
All loading happens in a TEMPORARY table private to the session; the staged
rows are validated against the expected shape of the IBM file before any
permanent object is created; the gated CREATE fails with ERROR 3141 on any
mismatch; and CREATE can only create - if the table already exists it
errors rather than touching it. The only DROP in the script is
`DROP TEMPORARY TABLE IF EXISTS` on the session's own scratch copy.

**"What did your data quality checks find?"**
Two REVIEW findings worth volunteering:
1. `TotalCharges` does not equal `MonthlyCharges x tenure` for most
   customers - only 731 rows match within $1, and 2,323 deviate by $50 or
   more, almost all long-tenured. A plausible explanation is price changes
   over the customer's life, but the data doesn't establish the cause, so
   any lifetime-value math on that column carries the caveat.
2. The 11 NULL `TotalCharges` rows are exactly the 11 recorded-tenure-0
   rows - new customers with no billed total yet. A known shape, not
   corruption.

**"Walk me through your modeling choices."**
- *Split:* stratified 60/20/20, seed 42. Stratified because churn is 26.5%,
  and an unlucky random split would distort the minority class.
- *Leak safety:* imputation, one-hot encoding and scaling all live inside
  the sklearn Pipeline and are fit on the training fold only. Nothing
  fitted on validation or test rows leaks into features.
- *Baseline:* a predict-nobody-leaves model already scores 73.5% accuracy,
  so accuracy alone is misleading. The baseline sits next to every model in
  the results table.
- *Selection:* best validation ROC-AUC wins; the test split is only for
  reporting, and every model's test numbers are shown, not just the
  winner's.

**"Why ROC-AUC and not accuracy?"**
With 26.5% churn, a trivial model gets 73.5% accuracy and learns nothing.
ROC-AUC measures ranking quality across all thresholds, which is what a
retention campaign actually uses - you contact the top of the ranked list,
not everyone a single threshold flags.

**"Your model only catches half the churners. Isn't that bad?"**
It's the honest result and it's worth saying plainly: recall is 44-53%
across all three models. A snapshot has no usage, billing-history or
service-quality features, so a recall ceiling is expected - though that's a
hypothesis about better data, not an established cause. It's exactly why
the project ends in an experiment design rather than a deployed score.

**"Logistic regression beat random forest?"**
On validation ROC-AUC, yes (0.860 validation for logistic regression). On
test they tie at 0.832. A tie on one test split is not evidence either is
better - and the 0.860 to 0.832 validation-to-test gap is itself worth
understanding before quoting any score.

**"What would you do next in a real job?"**
Three things, in order: rebuild features point-in-time (several columns -
contract, services, tenure, TotalCharges - may be recorded at or near the
moment of churn, so they're outcome-proximate), then run the
contract-conversion experiment in `docs/experiment.md`, and investigate the
electronic-check and fiber gaps with data this snapshot doesn't have
(payment friction, service quality).

## Numbers to know cold

| Number | Value |
| --- | --- |
| Customers / churned / overall rate | 7,043 / 1,869 / 26.5% |
| Churn by contract | month-to-month 42.7%, one-year 11.3%, two-year 2.8% |
| Priority segment | month-to-month, 0-12 months tenure: 28.3% of sample, 54.8% of churners |
| Biggest single segment (I8) | month-to-month / fiber / no support: 55.3% of all churned customers, 57.5% churn rate |
| Electronic check churn | 45.3% overall; 53.7% inside month-to-month |
| Churned monthly revenue | $139,130.85 |
| Baseline vs best model (test) | 73.5% accuracy / 0.500 AUC vs 78.9% accuracy / 0.832 AUC |
| Validation-to-test gap (selected model) | 0.860 to 0.832 ROC-AUC |

## The three caveats to volunteer before anyone asks

1. **It's a snapshot, not a survival curve.** A leaver's tenure is recorded
   when they left; a stayer's at the snapshot date. "New customers churn
   more" is partly a denominator effect.
2. **Everything is an association in a fictional sample.** Customers choose
   their contract, payment method and add-ons, so selection effects are
   everywhere. Each finding earns a test, not an automatic decision.
3. **It's the IBM sample data.** The findings demonstrate method. They say
   nothing about any real company, and the project deliberately invents no
   ROI number.
