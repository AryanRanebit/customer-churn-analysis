-- 01_setup.sql
-- Customer churn analysis - database setup (MySQL 8)
-- Creates the churn_analysis database (if missing) and the telco_churn table
-- from the bundled CSV.
--
-- Fail-closed design: this script cannot overwrite or append to any existing
-- table, and it refuses to create telco_churn at all unless the staged data
-- passes validation - even when the client is run with --force.
--   * All loading and cleaning happens in telco_churn_staging, a TEMPORARY
--     table private to this session, created fresh on every run. It can
--     never be, or modify, a pre-existing table.
--   * The final CREATE TABLE ... AS SELECT carries the validation in its
--     gate subquery: when the staged rows match the expected IBM file the
--     gate is 1 and the table is created; any mismatch raises an error and
--     no table is created. CREATE can only create - if telco_churn already
--     exists, the statement fails and the existing table is untouched.
-- A bad path, wrong line endings, or a truncated CSV therefore fails loudly
-- with no half-made table left behind: fix the cause and simply re-run.
-- To rebuild telco_churn deliberately, drop it yourself first
-- (DROP TABLE telco_churn) - that choice stays with you, not the script.

CREATE DATABASE IF NOT EXISTS churn_analysis;
USE churn_analysis;

-- Fresh session-private staging table. DROP TEMPORARY only ever affects this
-- session's own scratch copy (it matters only when you re-run the script in
-- the same client session); it cannot touch a permanent table, even one
-- that happens to share the name.
DROP TEMPORARY TABLE IF EXISTS telco_churn_staging;

-- Every column starts as TEXT on purpose: real CSVs are messy, and typing
-- later, deliberately, beats a failed import (11 blank TotalCharges here).
CREATE TEMPORARY TABLE telco_churn_staging (
    customerID       TEXT,
    gender           TEXT,
    SeniorCitizen    TEXT,
    Partner          TEXT,
    Dependents       TEXT,
    tenure           TEXT,
    PhoneService     TEXT,
    MultipleLines    TEXT,
    InternetService  TEXT,
    OnlineSecurity   TEXT,
    OnlineBackup     TEXT,
    DeviceProtection TEXT,
    TechSupport      TEXT,
    StreamingTV      TEXT,
    StreamingMovies  TEXT,
    Contract         TEXT,
    PaperlessBilling TEXT,
    PaymentMethod    TEXT,
    MonthlyCharges   TEXT,
    TotalCharges     TEXT,
    Churn            TEXT
);

-- Load the CSV. The path is read by the mysql CLIENT (LOCAL), so it is
-- relative to where you run the client. From the repo root the bundled file
-- is at data/raw/telco-customer-churn.csv; adjust if yours is elsewhere.
-- LOCAL INFILE needs local_infile enabled on BOTH ends: on the server
-- (check with: SHOW VARIABLES LIKE 'local_infile'; - if it is OFF, ask your
-- MySQL admin or enable it for your own local server) and on the client
-- (mysql client: start it with --local-infile=1; Workbench: enable it in the
-- connection's Advanced tab). No global setting is changed by this script.
-- The telco CSV from the GitHub link uses plain '\n' line endings, so the
-- terminator below is '\n'. If your copy came out of Windows with CRLF
-- endings, change it to '\r\n' instead. (Verified on MySQL 8.0: '\r\n'
-- silently loads 0 rows when the file uses plain '\n'.)
LOAD DATA LOCAL INFILE 'data/raw/telco-customer-churn.csv'
INTO TABLE telco_churn_staging
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- Cleaning: turn the 11 blank TotalCharges into proper NULLs.
-- (All 11 blanks are on rows with recorded tenure 0.) The raw CSV file on
-- disk is never modified - this only edits the imported rows.
UPDATE telco_churn_staging SET TotalCharges = NULL WHERE TRIM(TotalCharges) = '';

-- Type conversion, done explicitly after inspection.
ALTER TABLE telco_churn_staging
    MODIFY tenure          INT,
    MODIFY SeniorCitizen   TINYINT,
    MODIFY MonthlyCharges  DECIMAL(10,2),
    MODIFY TotalCharges    DECIMAL(12,2);

-- Validation: check the staged copy against the expected shape of the IBM
-- file - 7,043 rows, unique customer IDs, only Yes/No churn labels, exactly
-- 11 NULL TotalCharges, and plausible numeric ranges. (A temporary table can
-- only be referenced once per query in MySQL, hence the separate step.)
SELECT COUNT(*) = 7043
   AND COUNT(DISTINCT customerID) = 7043
   AND COALESCE(SUM(Churn NOT IN ('Yes', 'No')), 0) = 0
   AND SUM(TotalCharges IS NULL) = 11
   AND MIN(tenure) >= 0 AND MAX(tenure) <= 72
   AND MIN(MonthlyCharges) > 0 AND MAX(MonthlyCharges) < 1000
   AND COALESCE(MIN(TotalCharges), 0) >= 0
  INTO @staging_valid
  FROM telco_churn_staging;

-- Publish, gated on that check. The one-row gate subquery is evaluated
-- first (STRAIGHT_JOIN): when the staged data matched, gate is 1 and the
-- table is created. On any mismatch the gate runs JSON_EXTRACT on invalid
-- JSON, so the statement fails with ERROR 3141 (Invalid JSON text) right at
-- this line and NO table is created - under --force too, including when the
-- staging table is empty because the LOAD failed. Seeing ERROR 3141 here
-- means: the staged data did not match the expected IBM file; check the CSV
-- path and line endings, then re-run. CREATE TABLE can only create: if
-- telco_churn already exists, the statement fails and the existing table is
-- untouched.
CREATE TABLE telco_churn AS
SELECT s.*
  FROM (
        SELECT CASE WHEN @staging_valid IS TRUE THEN 1
                 ELSE JSON_EXTRACT('deliberately invalid JSON: the setup validation gate failed', '$')
               END AS gate
          FROM DUAL
       ) g
  STRAIGHT_JOIN telco_churn_staging s;

-- Quick checks after setup:
-- SELECT COUNT(*) FROM telco_churn;                 -- expect 7043
-- SELECT * FROM telco_churn LIMIT 5;
-- SELECT COUNT(*) FROM telco_churn WHERE TotalCharges IS NULL;  -- expect 11
