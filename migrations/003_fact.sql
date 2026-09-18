-- =====================================================================
-- 003  Fact table, partitioned by filing year
--
-- The LAR has NO natural key: the Bureau strips every loan identifier
-- before publication, and 2,081 groups of byte-identical rows exist
-- across the four years (2,776 excess rows). A surrogate is therefore
-- unavoidable, but an identity column would produce different keys on
-- every rebuild, which breaks reproducibility for anyone re-running the
-- repository.
--
-- The key used here is deterministic: md5 of the whole source row, plus
-- an occurrence number within that hash. Identical rows get sequential
-- occurrence numbers, so the pair is unique, stable across rebuilds, and
-- traceable back to the source row. application_sk is a compact bigint
-- derived from the same ordering, kept for join performance.
-- =====================================================================
DROP TABLE IF EXISTS marts.fct_application CASCADE;
CREATE TABLE marts.fct_application (
  activity_year            int     NOT NULL,
  application_sk           bigint  NOT NULL,
  row_hash                 char(32) NOT NULL,
  dup_seq                  int     NOT NULL,
  -- dimension keys
  lei                      text    NOT NULL,
  census_tract             text    NOT NULL,
  county_code              text,
  msa_md                   text,
  loan_product_sk          int     NOT NULL,
  dwelling_sk              int     NOT NULL,
  applicant_profile_sk     int     NOT NULL,
  -- outcome
  action_taken             text    NOT NULL,
  purchaser_type           text,
  preapproval              text,
  -- measures
  loan_amount              numeric,
  income_thousands         numeric,
  property_value           numeric,
  interest_rate            numeric,
  rate_spread              numeric,
  loan_to_value_ratio      numeric,
  debt_to_income_band      text,
  total_loan_costs         numeric,
  total_points_and_fees    numeric,
  origination_charges      numeric,
  discount_points          numeric,
  lender_credits           numeric,
  loan_term_months         numeric,
  intro_rate_period        numeric,
  multifamily_affordable_units numeric,
  -- why a measure is missing, preserved rather than collapsed to NULL
  income_na_reason         text,
  dti_na_reason            text,
  ltv_na_reason            text,
  rate_spread_na_reason    text,
  -- lender-side attributes
  applicant_credit_score_type    text,
  co_applicant_credit_score_type text,
  submission_of_application      text,
  initially_payable_to_institution text,
  hoepa_status             text,
  conforming_loan_limit    text,
  is_exempt_filer          boolean NOT NULL,
  county_was_repaired      boolean NOT NULL
) PARTITION BY LIST (activity_year);

CREATE TABLE marts.fct_application_2022 PARTITION OF marts.fct_application FOR VALUES IN (2022);
CREATE TABLE marts.fct_application_2023 PARTITION OF marts.fct_application FOR VALUES IN (2023);
CREATE TABLE marts.fct_application_2024 PARTITION OF marts.fct_application FOR VALUES IN (2024);
CREATE TABLE marts.fct_application_2025 PARTITION OF marts.fct_application FOR VALUES IN (2025);

INSERT INTO marts.fct_application
WITH keyed AS (
  SELECT l.*,
         md5(l::text) AS row_hash,
         row_number() OVER (PARTITION BY md5(l::text) ORDER BY l.lei, l.census_tract) AS dup_seq
  FROM raw.raw_lar l
)
SELECT
  k.activity_year::int,
  row_number() OVER (ORDER BY k.row_hash, k.dup_seq)::bigint AS application_sk,
  k.row_hash,
  k.dup_seq,
  k.lei,
  coalesce(nullif(k.census_tract,'NA'),'UNKNOWN'),
  coalesce(ref.repair_county(k.county_code, k.census_tract),'UNKNOWN'),
  coalesce(nullif(k.derived_msa_md,'NA'),'UNKNOWN'),
  p.loan_product_sk,
  w.dwelling_sk,
  a.applicant_profile_sk,
  k.action_taken,
  k.purchaser_type,
  k.preapproval,
  ref.to_num(k.loan_amount),
  ref.to_num(k.income),
  ref.to_num(k.property_value),
  ref.to_num(k.interest_rate),
  ref.to_num(k.rate_spread),
  ref.to_num(k.loan_to_value_ratio),
  nullif(nullif(k.debt_to_income_ratio,'NA'),'Exempt'),
  ref.to_num(k.total_loan_costs),
  ref.to_num(k.total_points_and_fees),
  ref.to_num(k.origination_charges),
  ref.to_num(k.discount_points),
  ref.to_num(k.lender_credits),
  ref.to_num(k.loan_term),
  ref.to_num(k.intro_rate_period),
  ref.to_num(k.multifamily_affordable_units),
  ref.na_reason(k.income),
  ref.na_reason(k.debt_to_income_ratio),
  ref.na_reason(k.loan_to_value_ratio),
  ref.na_reason(k.rate_spread),
  k.applicant_credit_score_type,
  k.co_applicant_credit_score_type,
  k.submission_of_application,
  k.initially_payable_to_institution,
  k.hoepa_status,
  k.conforming_loan_limit,
  (k.interest_rate = 'Exempt' OR k.loan_to_value_ratio = 'Exempt' OR k.total_loan_costs = 'Exempt'),
  (k.county_code = 'NA' AND k.census_tract <> 'NA')
FROM keyed k
JOIN marts.dim_loan_product p
  ON p.loan_type = k.loan_type AND p.loan_purpose = k.loan_purpose
 AND p.lien_status = k.lien_status AND p.derived_loan_product_type = k.derived_loan_product_type
 AND p.reverse_mortgage = k.reverse_mortgage AND p.open_end_line_of_credit = k.open_end_line_of_credit
 AND p.business_or_commercial_purpose = k.business_or_commercial_purpose
JOIN marts.dim_dwelling w
  ON w.derived_dwelling_category = k.derived_dwelling_category
 AND w.construction_method = k.construction_method
 AND w.total_units = k.total_units AND w.occupancy_type = k.occupancy_type
JOIN marts.dim_applicant_profile a
  ON a.derived_race = k.derived_race AND a.derived_ethnicity = k.derived_ethnicity
 AND a.derived_sex = k.derived_sex AND a.applicant_age = k.applicant_age
 AND a.co_applicant_age = k.co_applicant_age;
