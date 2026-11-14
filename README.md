# Customer Churn Analysis (SQL + Python)

An end-to-end analysis of customer churn: which customers leave a telecom
service, what they have in common, whether those signals predict churn, and
what a business could actually test next. Built to show how a business
problem moves from a raw file to a defensible answer - including the
unglamorous parts (import safety, data quality, schema design, regression
tests, leak-safe modeling) where analyses usually go wrong.

**Data:** IBM's fictional Telco customer sample - 7,043 customers, 21 columns.
This is sample data. Findings demonstrate method; they are not evidence about
any real company and do not prove savings.

Source: [IBM/telco-customer-churn-on-icp4d](https://github.com/IBM/telco-customer-churn-on-icp4d),
redistributed under the Apache License 2.0. The bundled copy at
`data/raw/telco-customer-churn.csv` is unmodified, and the full license text
ships with it at `data/raw/LICENSE`. (Upstream ships no NOTICE file.)

## The business question

A telecom company loses customers every month, and every customer who leaves
takes revenue with them. Retention offers cost money, so the business needs to
aim them at the right groups. This project answers: which customers are
leaving, what distinguishes them, and what intervention would be worth a
controlled test?

## Project layout

```
sql/01_setup.sql             safe CSV import: session-private staging, validation gate, typed table
sql/02_model.sql             normalized model: customers / customer_services / customer_billing
sql/03_data_quality.sql      12-check data quality battery (PASS / REVIEW statuses)
sql/04_views.sql             v_churn_enriched: one analysis-ready view over the model
sql/05_analysis.sql          descriptive queries: where do churn rates differ?
sql/06_insights.sql          insight queries: which differences are decision-relevant?
sql/07_regression_tests.sql  13-check battery: recomputes headline numbers, hard-fails on drift
analysis/run_analysis.py     runs the same SQL logic on SQLite as a second-engine cross-check
analysis/results.json        the captured outputs of that cross-check
analysis/run_churn_model.py  modeling layer: leak-safe sklearn pipelines, honest evaluation
analysis/model_results.json  measured validation/test metrics
analysis/figures/            confusion matrix, ROC curves, feature importance charts
dashboard/dashboard_spec.md  dashboard spec: pages, charts, expected values, binning definitions
dashboard/churn_dashboard_dataset.csv  the extract the dashboard reads
docs/experiment.md           design of a contract-conversion A/B test grounded in these findings
data/raw/                    the unmodified IBM CSV + Apache 2.0 LICENSE
```

## How to run

Requires MySQL 8 and the mysql client (or MySQL Workbench).

Run from the repository root (the setup script loads
`data/raw/telco-customer-churn.csv` relative to where you run the client),
in order:

```
mysql --local-infile=1 < sql/01_setup.sql
mysql --local-infile=1 < sql/02_model.sql
mysql --local-infile=1 < sql/03_data_quality.sql
mysql --local-infile=1 < sql/04_views.sql
mysql --local-infile=1 < sql/05_analysis.sql
mysql --local-infile=1 < sql/06_insights.sql
mysql --local-infile=1 < sql/07_regression_tests.sql
```

The last script prints a 13-row PASS table and ends with
`ALL TESTS PASSED`. If any check fails, it raises ERROR 3141 instead - a
broken run cannot be mistaken for a green one.

### Safety notes (01_setup.sql)

- **The setup script cannot overwrite or append to any existing table, even
  under `mysql --force`.** All loading and cleaning happens in
  `telco_churn_staging`, a TEMPORARY table that is private to your session
  and created fresh each run - it can never be, or modify, a pre-existing
  table. Before the final table is created, the staged rows are validated
  against the expected shape of the IBM file (7,043 rows, unique customer
  IDs, Yes/No churn labels, exactly 11 NULL TotalCharges, plausible numeric
  ranges); on any mismatch the gated `CREATE TABLE` fails with ERROR 3141 at
  the gate line and creates nothing. And `CREATE TABLE` can only create: if
  `telco_churn` already exists it fails, leaving that table untouched. So a
  bad path, wrong line endings, or a truncated CSV fails loudly with no
  half-made table left behind: fix the cause and re-run. To rebuild
  `telco_churn` deliberately, drop it yourself first - that choice is
  documented in the script, not made by it. (The only DROP in the script is
  `DROP TEMPORARY TABLE IF EXISTS`, which clears this session's own scratch
  copy and cannot touch a permanent table. The script creates no procedures
  or other permanent objects besides the `telco_churn` table.)
- **The model scripts are create-only too.** `02_model.sql` builds its three
  tables with `CREATE TABLE ... AS SELECT`; `04_views.sql` uses plain
  `CREATE VIEW`, so it errors rather than replace anything that already
  exists under that name. No script can append to, alter, or replace an
  existing object.
- **LOCAL INFILE needs `local_infile` on both ends:** on the server (check
  `SHOW VARIABLES LIKE 'local_infile';`) and on the client
  (`mysql --local-infile=1`, or the Workbench connection's Advanced tab).
  The script changes no global settings; enabling it for your own local
  server is your call.
- **The raw CSV is never modified.** It stays byte-for-byte intact in
  `data/raw/`. Cleaning (blank TotalCharges to NULL) and typing happen only
  on the imported rows inside MySQL, in the session-private staging copy.
- The setup script uses `LINES TERMINATED BY '\n'` because the IBM CSV uses
  plain `\n` endings - if your copy has CRLF (Windows) endings, switch that
  one line to `'\r\n'`.

## Design decisions (the parts worth talking about)

**Why a normalized model for a single flat file?**
The CSV arrives denormalized: one wide row mixing identity, subscribed
services, and billing. Real churn data lives in separate CRM, product, and
billing systems, so `02_model.sql` models that shape - three related tables
keyed by `customerID` - and `04_views.sql` joins them back into one
analysis-ready view. Working through the view means tenure banding, the
churn flag, and the add-on count are defined exactly once, not copied into
every query. `07_regression_tests.sql` proves the model reproduces the
staged raw table exactly (row counts, churn counts, revenue sums, NULL
pattern). If the two ever disagree, the model is wrong, not the analysis.

**Why keys without foreign keys?**
MySQL 8 forbids FK constraints in `CREATE TABLE ... AS SELECT` (ERROR 3978),
and adding them afterwards would mean ALTERing existing tables, which this
project refuses to do by design. For an analytics schema rebuilt from a
validated source, that is the right trade: the relationships are verified by
the data-quality battery (anti-join checks) instead of enforced.

**Why a data-quality battery with REVIEW statuses?**
`03_data_quality.sql` outputs one row per check with a PASS or REVIEW
status. REVIEW means "understood, not clean" - a reader should see it before
trusting the analysis. Two findings earn it:

- **`TotalCharges` does not equal `MonthlyCharges x tenure` for most
  customers.** 731 match within $1 (614 exactly, 613 of those at tenure 1
  where equality is forced); 2,323 deviate by $50 or more, almost all of
  them long-tenured (89 rows at recorded tenure 0-12 vs 1,254 at 49+).
  One plausible explanation is price changes over a customer's life, but
  this data does not establish the cause. Either way, `TotalCharges` is
  not a clean derived column, and any lifetime-value math on it carries
  that caveat.
- **The 11 NULL `TotalCharges` rows are exactly the 11 recorded-tenure-0
  rows** (both directions verified). New customers with no billed total
  yet - a known shape, not corruption.

**Why regression tests in SQL?**
Every headline number in this README is restated as an expected constant in
`07_regression_tests.sql` and recomputed from the staged raw table. Edit a
query, swap the CSV, or change the model, and the battery shows exactly
which number moved, then hard-fails. The battery is materialized into a
session-scoped TEMPORARY table so the displayed results and the gate read
the exact same rows.

**Why a second engine?**
`analysis/run_analysis.py` runs the same query logic against the CSV via
SQLite (in-memory, standard library only) and writes `results.json`. Every
number below was produced on MySQL 8.0.46 and independently reproduced on
SQLite 3. Two engines agreeing is cheap insurance against
dialect-specific bugs.

## Findings (verified on MySQL 8.0.46 and SQLite 3)

### Where churn rates differ (`05_analysis.sql`)

| Question | Result |
| --- | --- |
| Overall churn | 26.5% (1,869 of 7,043) |
| By contract | Month-to-month 42.7% (1,655/3,875) - One year 11.3% (166/1,473) - Two year 2.8% (48/1,695) |
| By recorded tenure | 0-12 mo 47.4% (1,037/2,186) - 13-24 mo 28.7% - 25-48 mo 20.4% - 49+ mo 9.5% |
| By payment | Electronic check 45.3% (1,071/2,365) - automatic methods 15-17% |
| By internet service | Fiber 41.9% (1,297/3,096) - DSL 19.0% - none 7.4% |
| Tech support | Without: 41.6% churn - With: 15.2% |
| Bills | Churned averaged $74.44/mo vs $61.27 stayed; medians $79.65 vs $64.43 (I11) |
| Churned monthly revenue | $139,130.85/month across 1,869 churned customers |

### Which differences are decision-relevant (`06_insights.sql`)

**1. Churn is concentrated, not spread out (I1, I2, I8).**
Month-to-month customers are 55.0% of the base but 88.6% of everyone who
left (and 86.9% of churned monthly revenue). A systematic scan of contract x
internet x support segments of 100+ customers (I8, with a running
cumulative-share window column) shows one segment - month-to-month / fiber
optic / no tech support - holding 55.3% of all churned customers by itself
(1,796 customers, 1,033 churned, 57.5% churn rate); the top three segments
cover 79.1%. About half the churn problem sits in about a quarter of the
base: that is what makes prioritization possible.

**2. The contract pattern is not just a tenure effect (I3).**
Month-to-month customers could churn more simply because they are newer.
Inside every tenure band the gap survives: 51.4/10.5/0.0
(month-to-month / one-year / two-year) at 0-12 months, 37.7/8.1/0.0 at
13-24, 32.9/10.6/2.2 at 25-48, 26.0/12.9/3.3 at 49+. Caveat: customers
choose their contract, so a surviving gap is still an association, not proof
that a longer contract itself retains anyone. Only an experiment can say -
see `docs/experiment.md`.

**3. The electronic-check pattern partly overlaps contract, but persists
(I4, I5).**
Electronic-check payers churn most overall (45.3%) and skew toward
month-to-month (47.7% of month-to-month vs 9.9% of two-year customers). But
inside month-to-month alone they still churn at 53.7% vs 31.6-34.1% for the
other methods. The data cannot say why - payment friction, or the kind of
customer who chooses manual payment; that is an investigation, not a
conclusion.

**4. Price alone does not explain churn (I6, I9).**
Fiber customers churn far more than DSL (41.9% vs 19.0%) and pay more
($91.5 vs $58.1 average). If price drove it, churn should rise with price.
It does not - two ways. Inside fiber, the $100+ tier churns least (28.3%),
the $70-90 tier most (51.1%). And across the whole base, NTILE(10) price
deciles (I9) rise from 8.7% and 9.4% churn at the bottom through a 40.9%
peak at decile 9, then DROP to 24.7% at the most expensive decile. A
simple "higher bill means higher churn" narrative is not supported by
these comparisons; causal price effects are not identified in this data,
and the fiber gap stays unexplained.

**5. The add-on ladder is the cleanest engagement gradient (I10).**
Inside fiber, churn falls monotonically with every optional service added:
60.4% at zero add-ons, 55.9 / 48.0 / 37.9 / 31.8 / 19.3, down to 9.2% at
all six. (The overall ladder needs care: the 0-add-on row mixes the 1,526
no-internet customers, who structurally cannot hold add-ons, with internet
customers holding none - from 1 add-on upward the overall gradient is
monotonic, 45.8% down to 5.3%.) Customers choose add-ons, so engaged
customers self-select - but a monotonic gradient inside one service type is
a bundling-test lead, not a chart to wave around.

**6. Inside the priority segment, support is a lead, not a conclusion (I7).**
Among month-to-month customers with 0-12 months of recorded tenure, churn
without tech support is 61.0% vs 42.8% with it - but the with-support group
is only 243 customers, so treat this as a hypothesis to test.

## What a business could actually test

`docs/experiment.md` designs the top-priority test end to end: a
contract-conversion experiment aimed at month-to-month customers
(stratified by internet service and support status, since I4/I7 show those
shift churn independently of contract). It covers the hypothesis, unit of
randomization, intention-to-treat primary metric, guardrails, the decision
rule, and - deliberately - the inputs only the business can supply (discount
size, sample size, what churn costs). With synthetic data there is no honest
ROI number, and this project does not invent one.

Second and third: an electronic-check investigation (cheap first steps: a
short churned-customer survey or a measured autopay-nudge test) and a fiber
gap investigation (service quality, expectations, or bundling - explicitly
not a price cut first, since I6 and I9 give no support to a simple
price-driven story).

## The modeling layer (`analysis/run_churn_model.py`)

The SQL findings say *where churn was*; the modeling layer asks whether
those same signals *predict* churn, under honest measurement rules:

- **Leak-safe pipelines.** All preprocessing (median imputation for the 11
  missing `TotalCharges`, one-hot encoding, scaling) lives inside the
  sklearn `Pipeline` and is fit on the training fold only.
- **A stratified 60/20/20 split (seed 42).** Model selection happens on
  the validation split (best validation ROC-AUC wins); the test split is
  reserved for reporting, and every model's test numbers are shown
  transparently, not only the winner's. Class imbalance is 26.5%, so the
  majority-class baseline (73.5% accuracy, 0.50 AUC) is reported next to
  every model.
- **Measured on this data, not copied.** Test-split results:

| Model | Accuracy | Precision | Recall | ROC-AUC |
| --- | --- | --- | --- | --- |
| Baseline (predict nobody leaves) | 73.5% | - | 0.0% | 0.500 |
| Logistic regression | 78.9% | 62.0% | 52.7% | 0.832 |
| Decision tree (depth 6) | 78.1% | 62.3% | 44.1% | 0.819 |
| Random forest | 78.5% | 63.7% | 44.1% | 0.832 |

Logistic regression was selected on validation ROC-AUC. On test it scores
0.832 vs 0.860 on validation - the gap between validation and test is
itself worth understanding before quoting any score. Note the test table
shows logistic regression and random forest tied at 0.832 AUC; that is a
tie on one test split, not evidence one is better.

Two honest reads from this layer:

1. **The models rank the same signals the SQL found.** Random-forest
   feature importance is led by tenure, month-to-month contract,
   TotalCharges, no online security, no tech support, fiber, and
   electronic check. This is the same data seen through a second method,
   not independent evidence - both layers read the same snapshot.
2. **Prediction has a ceiling here, and that is a finding.** Every model
   misses about half the churners (recall 44-53%). A plausible reason is
   that a snapshot has no usage, billing-history, or service-quality
   features - but that is a hypothesis about better data, not an
   established cause. It is exactly why the project ends in an experiment
   design rather than a deployed score.

Two leakage caveats apply. A random split on a retrospective snapshot
measures interpolation, not prospective performance on future customers.
And even with preprocessing fit on training folds only, several columns
(contract, services, tenure, TotalCharges) may be outcome-proximate -
recorded at or near the moment of churn - so a real deployment would need
a point-in-time feature rebuild before trusting these scores. Charts are
in `analysis/figures/`; metrics in `analysis/model_results.json`.

## The dashboard (dashboard/)

The BI layer is a Looker Studio report ("Customer Churn Analysis") built on
`dashboard/churn_dashboard_dataset.csv`, an extract of `v_churn_enriched`.
Looker Studio is free and the report is private in the builder's Google
account; the CSV contains only the fictional sample. Three pages:

- **Overview** - headline scorecards (7,043 customers, 1,869 churned, 26.5%
  churn rate, $139,130.85 churned monthly bills), filter controls, and the
  contract and tenure-band churn charts.
- **Drivers** - churn by monthly bill band, payment method (45.3% / 19.1% /
  16.7% / 15.2%, percent axis), fiber add-on ladder, and the contract x
  support x internet segment table with separate dimension columns.
- **Model results** - the measured model scores, confusion matrix, and
  random-forest feature importances, with the same retrospective-data
  caveats as the modeling layer.

`dashboard/dashboard_spec.md` carries every expected value, including the
one place the dashboard and SQL legitimately differ: the bill chart uses
fixed CASE bands over MonthlyCharges while I9 uses NTILE(10) equal-count
deciles - the spec records both series and why they differ at tie-heavy
boundary bills.

## Caveats that apply to everything above

- **This is a snapshot, not a survival curve.** A leaver's tenure is
  recorded when they left; a stayer's tenure is recorded at the snapshot
  date. Tenure bands describe who is in the data now, not the tracked
  history of a cohort, and "new customers churn more" is partly a
  denominator effect.
- **Every comparison is an association in a fictional sample.** Nothing
  here is a causal claim, a prediction, or a money-saved estimate. Each
  finding earns a test with a measured result, not an automatic decision.
- **Small segments are flagged, not spun.** Where a group is small enough
  to wobble (I7's 243-customer with-support cell), the README says so.

## Scope and next steps

The project now has five connected layers: safe SQL import and a normalized
model, a data-quality battery and regression tests, descriptive + insight
SQL (window functions: NTILE, ROW_NUMBER, running shares), a leak-safe
Python modeling layer with measured, honestly-reported scores, and a BI
dashboard in Looker Studio over the same metrics. The natural next step is
a walkthrough that makes every query and every score explainable in an
interview.
