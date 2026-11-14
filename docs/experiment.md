# From analysis to experiment: a contract-conversion test

The SQL in this project reads a snapshot. It can say where churn *is*
concentrated, not what *causes* it, and not what an intervention would
change. This document closes that gap on paper: it designs the experiment a
team would run to test the most promising intervention the analysis points
to, and it is explicit about the inputs only the business can supply.

Everything below is grounded in the project's own findings. Nothing here
claims a result: the experiment has not been run.

## The finding being tested

`sql/06_insights.sql` (I1, I8) shows that month-to-month customers hold
86.9% of the monthly revenue carried by churned customers, and that one
segment, month-to-month / fiber optic / no-support, is 55.3% of all churned
customers (1796 customers, 1033 churned, 57.5% churn rate). Contract length
is the single strongest structural split in the data: 42.7% churn on
month-to-month vs 11.3% on one-year and 2.8% on two-year contracts
(`sql/05_analysis.sql`, Q2).

The natural intervention: move month-to-month customers onto a one-year
contract.

## Why the analysis alone cannot justify it

The 42.7% vs 11.3% gap is not the effect of a contract. Customers *choose*
their contract; people who expect to stay choose longer ones. Converting a
reluctant month-to-month customer does not turn them into the kind of
customer who voluntarily picks a one-year plan. Estimating the true effect
requires randomization.

The snapshot has a second caveat: tenure is recorded at churn for customers
who left and at the snapshot date for those who stayed, so "new customers
churn more" is partly a denominator effect, not a survival curve.

## Experiment design

**Hypothesis.** Offering month-to-month customers a one-year contract at a
modest discount increases 12-month retention relative to the same customers
receiving no offer.

**Unit of randomization.** The customer (customerID). Not the household,
not the billing account batch - one row, one coin flip, so treatment is
independent across units.

**Assignment.** Eligible pool: active month-to-month customers with tenure
of at least 3 months (the 0-2 month window is where early-life churn
concentrates, and brand-new customers have not seen enough of the product
to value a commitment). Split 50/50, stratified by internet service type
and support status, since the analysis shows these shift churn
independently of contract (I4, I7).

**Treatment.** An offer: switch to a one-year contract at a discount off
the current monthly price. Control: no offer, business as usual.

**Primary metric.** Fraction of each arm still active (not churned) at 12
months after assignment. Measured for everyone assigned, whether or not
they took the offer (intention-to-treat). A take-up-adjusted read comes
second; the headline number is what rolling out the offer would change.

**Guardrail metrics.** Discount cost per retained customer; monthly revenue
per retained customer vs control; churn among treated customers who
declined the offer (an offer can remind people they were thinking of
leaving); support-ticket volume in the treated arm.

**Decision rule.** Ship the offer to the eligible population if the treated
arm's 12-month retention beats control by at least the pre-registered
minimum detectable effect *and* guardrails stay within bounds. If the lift
is smaller, or the offer churns decliners, do not ship. A null result is a
result: it means the contract gap is mostly selection, and budget moves to
the support and early-tenure problems instead.

## Inputs only the business can supply

The analysis cannot set these, and guessing them would fabricate the
conclusion:

- **The discount size.** Too small to matter and the test is uninformative;
  too large and the cost per retained customer breaks the guardrail. This
  is a finance decision.
- **The minimum detectable effect and sample size.** These need the churn
  baseline and the smallest lift worth shipping for, which depends on
  margins this dataset does not contain.
- **What churn costs.** Retention value, support cost, and discount cost
  all live outside the dataset. This document deliberately avoids any ROI
  arithmetic; with synthetic data there is no honest number to put there.
- **Offer channel and legal terms.** Who sees the offer, and whether an
  accepted offer is binding.

## What the SQL contributes to the test

The eligibility query, the stratification keys, and the baseline rates all
come directly from `v_churn_enriched`: the pool definition is `Contract =
'Month-to-month' AND tenure >= 3 AND churned = 0` under the snapshot
semantics, the strata are InternetService and the support flag from I7, and
the baseline rates for the sample-size discussion are the I1 and Q2 numbers.
The experiment measures against what the analysis already computed, which
is what makes the two documents one project.
