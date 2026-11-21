#!/usr/bin/env python3
"""Sandbox runner: executes the same analysis logic as sql/05_analysis.sql and
sql/06_insights.sql against the raw CSV via SQLite, so every number in the
README is verified on a second engine (MySQL 8 is the primary).

Importable as a module (build_db / run_queries) so the regression tests in
analysis/tests/ can recompute every query without subprocess overhead; running
it as a script behaves exactly as before and rewrites analysis/results.json.
"""
import csv, json, sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSV = ROOT / 'data' / 'raw' / 'telco-customer-churn.csv'
OUT = ROOT / 'analysis' / 'results.json'

SCHEMA = '''CREATE TABLE telco_churn (
    customerID TEXT, gender TEXT, SeniorCitizen INTEGER, Partner TEXT,
    Dependents TEXT, tenure INTEGER, PhoneService TEXT, MultipleLines TEXT,
    InternetService TEXT, OnlineSecurity TEXT, OnlineBackup TEXT,
    DeviceProtection TEXT, TechSupport TEXT, StreamingTV TEXT,
    StreamingMovies TEXT, Contract TEXT, PaperlessBilling TEXT,
    PaymentMethod TEXT, MonthlyCharges REAL, TotalCharges REAL, Churn TEXT)'''

def load_rows(con):
    with open(CSV, newline='') as f:
        for r in csv.DictReader(f):
            con.execute('INSERT INTO telco_churn VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                (r['customerID'], r['gender'], int(r['SeniorCitizen']), r['Partner'],
                 r['Dependents'], int(r['tenure']), r['PhoneService'], r['MultipleLines'],
                 r['InternetService'], r['OnlineSecurity'], r['OnlineBackup'],
                 r['DeviceProtection'], r['TechSupport'], r['StreamingTV'],
                 r['StreamingMovies'], r['Contract'], r['PaperlessBilling'],
                 r['PaymentMethod'], float(r['MonthlyCharges']),
                 float(r['TotalCharges']) if r['TotalCharges'].strip() else None,
                 r['Churn']))

def build_db():
    con = sqlite3.connect(':memory:')
    con.execute(SCHEMA)
    load_rows(con)
    return con

QUERIES = {
'Q1_overall': """SELECT COUNT(*) customers, SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct FROM telco_churn""",
'Q2_contract': """SELECT Contract, COUNT(*) customers, SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct FROM telco_churn
 GROUP BY Contract ORDER BY churn_pct DESC""",
'Q3_tenure_band': """SELECT CASE WHEN tenure<=12 THEN '0-12'
 WHEN tenure<=24 THEN '13-24' WHEN tenure<=48 THEN '25-48'
 ELSE '49+' END tenure_band, COUNT(*) customers, SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct FROM telco_churn
 GROUP BY tenure_band ORDER BY MIN(tenure)""",
'Q4_internet': """SELECT InternetService, COUNT(*) customers, SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct FROM telco_churn
 GROUP BY InternetService ORDER BY churn_pct DESC""",
'Q5_payment': """SELECT PaymentMethod, COUNT(*) customers, SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct FROM telco_churn
 GROUP BY PaymentMethod ORDER BY churn_pct DESC""",
'Q6_charges': """SELECT Churn, COUNT(*) customers, ROUND(AVG(MonthlyCharges),2) avg_monthly_charges,
 ROUND(AVG(tenure),1) avg_tenure_months FROM telco_churn GROUP BY Churn""",
'Q7_techsupport': """SELECT TechSupport, COUNT(*) customers, SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct FROM telco_churn
 GROUP BY TechSupport ORDER BY churn_pct DESC""",
'Q8_segment': """SELECT CASE WHEN Contract='Month-to-month' AND tenure<=12
 THEN 'Month-to-month, tenure 0-12' ELSE 'Everyone else' END segment,
 COUNT(*) customers, SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct FROM telco_churn GROUP BY segment""",
'Q9_revenue': """SELECT ROUND(SUM(MonthlyCharges),2) monthly_revenue_from_churned,
 COUNT(*) churned_customers FROM telco_churn WHERE Churn='Yes'""",
'I1_contribution_contract': """SELECT Contract, COUNT(*) customers,
 ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM telco_churn),1) pct_of_customers,
 SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/(SELECT COUNT(*) FROM telco_churn WHERE Churn='Yes'),1) pct_of_all_churn,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct,
 ROUND(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges END),2) churned_monthly_revenue,
 ROUND(100.0*SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges END)
   /(SELECT SUM(MonthlyCharges) FROM telco_churn WHERE Churn='Yes'),1) pct_of_churned_revenue
 FROM telco_churn GROUP BY Contract ORDER BY churned DESC""",
'I2_priority_segment': """SELECT CASE WHEN Contract='Month-to-month' AND tenure<=12
 THEN 'Month-to-month, tenure 0-12' ELSE 'Everyone else' END segment,
 COUNT(*) customers,
 ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM telco_churn),1) pct_of_customers,
 SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/(SELECT COUNT(*) FROM telco_churn WHERE Churn='Yes'),1) pct_of_all_churn,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct,
 ROUND(SUM(CASE WHEN Churn='Yes' THEN MonthlyCharges END),2) churned_monthly_revenue
 FROM telco_churn GROUP BY segment ORDER BY segment DESC""",
'I3_contract_within_tenure': """SELECT CASE WHEN tenure<=12 THEN '0-12'
 WHEN tenure<=24 THEN '13-24' WHEN tenure<=48 THEN '25-48' ELSE '49+' END tenure_band,
 Contract, COUNT(*) customers, SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct FROM telco_churn
 GROUP BY tenure_band, Contract ORDER BY tenure_band, churn_pct DESC""",
'I4_payment_within_mtm': """SELECT PaymentMethod, COUNT(*) customers,
 SUM(Churn='Yes') churned, ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct
 FROM telco_churn WHERE Contract='Month-to-month'
 GROUP BY PaymentMethod ORDER BY churn_pct DESC""",
'I5_echeck_mix_by_contract': """SELECT Contract, COUNT(*) customers,
 SUM(PaymentMethod='Electronic check') echeck_customers,
 ROUND(100.0*SUM(PaymentMethod='Electronic check')/COUNT(*),1) echeck_pct
 FROM telco_churn GROUP BY Contract ORDER BY echeck_pct DESC""",
'I6_fiber_price': """SELECT CASE WHEN MonthlyCharges<70 THEN 'under $70'
 WHEN MonthlyCharges<90 THEN '$70-90' WHEN MonthlyCharges<100 THEN '$90-100'
 ELSE '$100+' END price_tier, COUNT(*) customers, SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct
 FROM telco_churn WHERE InternetService='Fiber optic'
 GROUP BY price_tier ORDER BY price_tier""",
'I7_support_in_priority_segment': """SELECT TechSupport, COUNT(*) customers,
 SUM(Churn='Yes') churned, ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct
 FROM telco_churn WHERE Contract='Month-to-month' AND tenure<=12
 GROUP BY TechSupport ORDER BY churn_pct DESC""",
'I8_pareto': """SELECT Contract || ' / ' || InternetService || ' / ' ||
 CASE TechSupport WHEN 'Yes' THEN 'support' WHEN 'No' THEN 'no-support'
 ELSE 'no-internet' END segment, COUNT(*) customers, SUM(Churn='Yes') churned,
 ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct,
 ROUND(100.0*SUM(Churn='Yes')/(SELECT SUM(Churn='Yes') FROM telco_churn),1) pct_of_all_churn,
 ROUND(100.0*SUM(SUM(Churn='Yes')) OVER (ORDER BY SUM(Churn='Yes') DESC
   ROWS UNBOUNDED PRECEDING)/(SELECT SUM(Churn='Yes') FROM telco_churn),1) cumulative_pct_of_churn
 FROM telco_churn GROUP BY segment HAVING customers >= 100 ORDER BY churned DESC""",
'I9_price_deciles': """SELECT decile, COUNT(*) customers,
 ROUND(MIN(MonthlyCharges),2) min_bill, ROUND(MAX(MonthlyCharges),2) max_bill,
 SUM(Churn='Yes') churned, ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct
 FROM (SELECT MonthlyCharges, Churn,
 NTILE(10) OVER (ORDER BY MonthlyCharges) decile FROM telco_churn) d
 GROUP BY decile ORDER BY decile""",
'I10_addon_ladder': """SELECT ((OnlineSecurity='Yes')+(OnlineBackup='Yes')+(DeviceProtection='Yes')
 +(TechSupport='Yes')+(StreamingTV='Yes')+(StreamingMovies='Yes')) addon_count, COUNT(*) customers,
 SUM(Churn='Yes') churned, ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct
 FROM telco_churn GROUP BY addon_count ORDER BY addon_count""",
'I10b_addon_ladder_fiber': """SELECT ((OnlineSecurity='Yes')+(OnlineBackup='Yes')+(DeviceProtection='Yes')
 +(TechSupport='Yes')+(StreamingTV='Yes')+(StreamingMovies='Yes')) addon_count, COUNT(*) customers,
 SUM(Churn='Yes') churned, ROUND(100.0*SUM(Churn='Yes')/COUNT(*),1) churn_pct
 FROM telco_churn WHERE InternetService='Fiber optic'
 GROUP BY addon_count ORDER BY addon_count""",
'I11_median_charges': """SELECT Churn, COUNT(*) customers,
 ROUND(AVG(MonthlyCharges),2) median_monthly_charges
 FROM (SELECT Churn, MonthlyCharges,
 ROW_NUMBER() OVER (PARTITION BY Churn ORDER BY MonthlyCharges) rn,
 COUNT(*) OVER (PARTITION BY Churn) n FROM telco_churn) ranked
 WHERE rn IN ((n+1)/2, (n+2)/2) GROUP BY Churn""",
}

def run_queries(con):
    results = {}
    for name, q in QUERIES.items():
        cur = con.execute(q)
        cols = [d[0] for d in cur.description]
        results[name] = [dict(zip(cols, r)) for r in cur.fetchall()]
    return results

def main():
    results = run_queries(build_db())
    for name, rows in results.items():
        print(f'== {name} ==')
        for r in rows:
            print('  ', r)
    with open(OUT, 'w') as f:
        json.dump(results, f, indent=2)
    print('saved analysis/results.json')

if __name__ == '__main__':
    main()
