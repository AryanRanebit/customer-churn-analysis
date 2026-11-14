-- 02_model.sql
-- Customer churn analysis - normalized model (MySQL 8)
-- Run after 01_setup.sql, against churn_analysis.
--
-- The CSV arrives denormalized: one wide row per customer mixing identity,
-- subscribed services, and billing. Real churn data lives in separate CRM,
-- product, and billing systems, so this project models that shape: three
-- related tables keyed by customerID, instead of one flat file. All later
-- analysis reads a view (04_views.sql) that joins them back together, and
-- 07_regression_tests.sql proves the model reproduces the staged table
-- exactly. If the two ever disagree, the model is wrong, not the analysis.
--
-- Design notes:
--   * Fail-closed like 01_setup.sql: CREATE TABLE ... AS SELECT can only
--     create. If any of these tables already exists, the run errors and
--     changes nothing - there is no INSERT into any existing table.
--   * Keys are declared, not enforced by foreign keys: MySQL 8 does not
--     allow FK constraints in CREATE TABLE ... AS SELECT (ERROR 3978), and
--     adding them afterwards would mean ALTERing existing tables, which
--     this project refuses to do. For an analytics schema rebuilt from a
--     validated source this is the right trade: relationships are verified
--     by the data-quality battery (03_data_quality.sql) instead of enforced.
--   * TotalCharges stays nullable: the 11 recorded-tenure-0 customers have
--     no billed total yet. NOT NULL on everything else - 01_setup.sql
--     validated it, and strict mode would fail the CREATE otherwise.

USE churn_analysis;

CREATE TABLE customers (
    customerID       VARCHAR(10) PRIMARY KEY,
    gender           VARCHAR(10) NOT NULL,
    SeniorCitizen    TINYINT     NOT NULL,
    Partner          VARCHAR(3)  NOT NULL,
    Dependents       VARCHAR(3)  NOT NULL,
    tenure           INT         NOT NULL,
    Contract         VARCHAR(20) NOT NULL,
    PaperlessBilling VARCHAR(3)  NOT NULL,
    Churn            VARCHAR(3)  NOT NULL
) AS
SELECT customerID, gender, SeniorCitizen, Partner, Dependents,
       tenure, Contract, PaperlessBilling, Churn
FROM telco_churn;

CREATE TABLE customer_services (
    customerID       VARCHAR(10) PRIMARY KEY,
    PhoneService     VARCHAR(3)  NOT NULL,
    MultipleLines    VARCHAR(20) NOT NULL,
    InternetService  VARCHAR(20) NOT NULL,
    OnlineSecurity   VARCHAR(20) NOT NULL,
    OnlineBackup     VARCHAR(20) NOT NULL,
    DeviceProtection VARCHAR(20) NOT NULL,
    TechSupport      VARCHAR(20) NOT NULL,
    StreamingTV      VARCHAR(20) NOT NULL,
    StreamingMovies  VARCHAR(20) NOT NULL
) AS
SELECT customerID, PhoneService, MultipleLines, InternetService,
       OnlineSecurity, OnlineBackup, DeviceProtection, TechSupport,
       StreamingTV, StreamingMovies
FROM telco_churn;

CREATE TABLE customer_billing (
    customerID     VARCHAR(10) PRIMARY KEY,
    PaymentMethod  VARCHAR(40)   NOT NULL,
    MonthlyCharges DECIMAL(10,2) NOT NULL,
    TotalCharges   DECIMAL(12,2) NULL
) AS
SELECT customerID, PaymentMethod, MonthlyCharges, TotalCharges
FROM telco_churn;
