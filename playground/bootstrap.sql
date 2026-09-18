-- =====================================================================
-- Playground bootstrap
--
-- Recreates the PostgreSQL schema namespaces over the Parquet exports so
-- that the queries published in docs/08_analysis.md run here unchanged.
-- Without this every query would have to be rewritten to read
-- 'fct_application_2024.parquet' instead of marts.fct_application, and the
-- repository would be shipping two versions of every query.
--
-- The fact view is a UNION ALL over the four year files, which keeps the
-- partition-level file layout that makes the HTTP range requests efficient
-- while presenting one table to the user.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS marts;
CREATE SCHEMA IF NOT EXISTS ref;

CREATE OR REPLACE VIEW marts.fct_application AS
  SELECT * FROM read_parquet([
    'data/fct_application_2022.parquet',
    'data/fct_application_2023.parquet',
    'data/fct_application_2024.parquet',
    'data/fct_application_2025.parquet']);

CREATE OR REPLACE VIEW marts.dim_date              AS SELECT * FROM 'data/dim_date.parquet';
CREATE OR REPLACE VIEW marts.dim_institution       AS SELECT * FROM 'data/dim_institution.parquet';
CREATE OR REPLACE VIEW marts.dim_tract             AS SELECT * FROM 'data/dim_tract.parquet';
CREATE OR REPLACE VIEW marts.dim_county            AS SELECT * FROM 'data/dim_county.parquet';
CREATE OR REPLACE VIEW marts.dim_msa               AS SELECT * FROM 'data/dim_msa.parquet';
CREATE OR REPLACE VIEW marts.dim_loan_product      AS SELECT * FROM 'data/dim_loan_product.parquet';
CREATE OR REPLACE VIEW marts.dim_dwelling          AS SELECT * FROM 'data/dim_dwelling.parquet';
CREATE OR REPLACE VIEW marts.dim_applicant_profile AS SELECT * FROM 'data/dim_applicant_profile.parquet';

CREATE OR REPLACE VIEW marts.br_application_race      AS SELECT * FROM 'data/br_application_race.parquet';
CREATE OR REPLACE VIEW marts.br_application_ethnicity AS SELECT * FROM 'data/br_application_ethnicity.parquet';
CREATE OR REPLACE VIEW marts.br_denial_reason         AS SELECT * FROM 'data/br_denial_reason.parquet';
CREATE OR REPLACE VIEW marts.br_underwriting_system   AS SELECT * FROM 'data/br_underwriting_system.parquet';
CREATE OR REPLACE VIEW marts.quarantine_application   AS SELECT * FROM 'data/quarantine_application.parquet';

CREATE OR REPLACE VIEW ref.ref_code          AS SELECT * FROM 'data/ref_code.parquet';
CREATE OR REPLACE VIEW ref.assertion_catalog AS SELECT * FROM 'data/assertion_catalog.parquet';

-- The labelled views from migrations/007_views.sql, so that the analysis
-- queries can use is_decided / is_denied here exactly as they do in Postgres.
CREATE OR REPLACE VIEW marts.v_application AS
SELECT f.activity_year, f.application_sk,
       i.institution_name,
       ra.label  AS action_taken_label,
       pu.label  AS loan_purpose,
       ap.derived_race     AS applicant_race,
       ap.derived_ethnicity AS applicant_ethnicity,
       ap.derived_sex      AS applicant_sex,
       t.minority_population_pct AS tract_minority_pct,
       f.census_tract, f.lei,
       f.loan_amount, f.income_thousands, f.rate_spread, f.interest_rate,
       f.loan_to_value_ratio, f.debt_to_income_band,
       (f.action_taken IN ('1','3')) AS is_decided,
       (f.action_taken = '3')        AS is_denied,
       (f.action_taken = '1')        AS is_originated,
       (f.action_taken = '5')        AS is_closed_incomplete
FROM marts.fct_application f
JOIN marts.dim_institution i       ON i.activity_year = f.activity_year AND i.lei = f.lei
JOIN marts.dim_applicant_profile ap ON ap.applicant_profile_sk = f.applicant_profile_sk
JOIN marts.dim_loan_product p      ON p.loan_product_sk = f.loan_product_sk
JOIN marts.dim_tract t             ON t.activity_year = f.activity_year AND t.census_tract = f.census_tract
JOIN ref.ref_code ra ON ra.code_field = 'action_taken' AND ra.code_value = f.action_taken
JOIN ref.ref_code pu ON pu.code_field = 'loan_purpose' AND pu.code_value = p.loan_purpose;

CREATE OR REPLACE VIEW marts.v_denial_reason AS
SELECT b.activity_year, b.application_sk, b.reason_ordinal,
       c.label AS reason, (f.action_taken = '3') AS is_denied
FROM marts.br_denial_reason b
JOIN marts.fct_application f ON f.activity_year = b.activity_year AND f.application_sk = b.application_sk
JOIN ref.ref_code c ON c.code_field = 'denial_reason' AND c.code_value = b.denial_reason_code;

CREATE OR REPLACE VIEW marts.v_application_race AS
SELECT b.activity_year, b.application_sk, b.party, b.slot,
       b.race_code, left(b.race_code, 1) AS race_top_level, c.label AS race
FROM marts.br_application_race b
LEFT JOIN ref.ref_code c ON c.code_field = 'race' AND c.code_value = b.race_code;
