-- =====================================================================
-- 000  Raw layer: tables shaped exactly like the published files.
-- Everything is text. No casting, no cleaning, no opinions. This is
-- the as-received layer and it is never edited; all interpretation
-- happens downstream where it can be inspected and re-run.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS raw;
DROP TABLE IF EXISTS raw.raw_lar CASCADE;
CREATE TABLE raw.raw_lar (
  activity_year text,
  lei text,
  derived_msa_md text,
  state_code text,
  county_code text,
  census_tract text,
  conforming_loan_limit text,
  derived_loan_product_type text,
  derived_dwelling_category text,
  derived_ethnicity text,
  derived_race text,
  derived_sex text,
  action_taken text,
  purchaser_type text,
  preapproval text,
  loan_type text,
  loan_purpose text,
  lien_status text,
  reverse_mortgage text,
  open_end_line_of_credit text,
  business_or_commercial_purpose text,
  loan_amount text,
  loan_to_value_ratio text,
  interest_rate text,
  rate_spread text,
  hoepa_status text,
  total_loan_costs text,
  total_points_and_fees text,
  origination_charges text,
  discount_points text,
  lender_credits text,
  loan_term text,
  prepayment_penalty_term text,
  intro_rate_period text,
  negative_amortization text,
  interest_only_payment text,
  balloon_payment text,
  other_nonamortizing_features text,
  property_value text,
  construction_method text,
  occupancy_type text,
  manufactured_home_secured_property_type text,
  manufactured_home_land_property_interest text,
  total_units text,
  multifamily_affordable_units text,
  income text,
  debt_to_income_ratio text,
  applicant_credit_score_type text,
  co_applicant_credit_score_type text,
  applicant_ethnicity_1 text,
  applicant_ethnicity_2 text,
  applicant_ethnicity_3 text,
  applicant_ethnicity_4 text,
  applicant_ethnicity_5 text,
  co_applicant_ethnicity_1 text,
  co_applicant_ethnicity_2 text,
  co_applicant_ethnicity_3 text,
  co_applicant_ethnicity_4 text,
  co_applicant_ethnicity_5 text,
  applicant_ethnicity_observed text,
  co_applicant_ethnicity_observed text,
  applicant_race_1 text,
  applicant_race_2 text,
  applicant_race_3 text,
  applicant_race_4 text,
  applicant_race_5 text,
  co_applicant_race_1 text,
  co_applicant_race_2 text,
  co_applicant_race_3 text,
  co_applicant_race_4 text,
  co_applicant_race_5 text,
  applicant_race_observed text,
  co_applicant_race_observed text,
  applicant_sex text,
  co_applicant_sex text,
  applicant_sex_observed text,
  co_applicant_sex_observed text,
  applicant_age text,
  co_applicant_age text,
  applicant_age_above_62 text,
  co_applicant_age_above_62 text,
  submission_of_application text,
  initially_payable_to_institution text,
  aus_1 text,
  aus_2 text,
  aus_3 text,
  aus_4 text,
  aus_5 text,
  denial_reason_1 text,
  denial_reason_2 text,
  denial_reason_3 text,
  denial_reason_4 text,
  tract_population text,
  tract_minority_population_percent text,
  ffiec_msa_md_median_family_income text,
  tract_to_msa_income_percentage text,
  tract_owner_occupied_units text,
  tract_one_to_four_family_homes text,
  tract_median_age_of_housing_units text
);

DROP TABLE IF EXISTS raw.raw_ts CASCADE;
CREATE TABLE raw.raw_ts (
  activity_year text, calendar_quarter text, lei text, tax_id text,
  agency_code text, respondent_name text, respondent_state text,
  respondent_city text, respondent_zip_code text, lar_count text
);

DROP TABLE IF EXISTS raw.raw_msamd CASCADE;
CREATE TABLE raw.raw_msamd (
  msa_md text, msa_md_name text, state text, activity_year int
);

-- The Philadelphia Fed lender file ("Avery file"): 73 columns, all text.
-- Created by the loader from the spreadsheet header so it stays in step
-- with the source if the Fed adds a column.

DROP TABLE IF EXISTS ref.ref_source_vintage CASCADE;
CREATE SCHEMA IF NOT EXISTS ref;
CREATE TABLE ref.ref_source_vintage (
  activity_year int PRIMARY KEY,
  dataset       text NOT NULL,
  freeze_date   date NOT NULL,
  note          text
);
INSERT INTO ref.ref_source_vintage VALUES
 (2022,'Three Year National Loan-Level','2025-12-31','Most complete vintage: 34 months of resubmissions'),
 (2023,'One Year National Loan-Level','2025-05-19','12 months of resubmissions'),
 (2024,'One Year National Loan-Level','2026-06-02','12 months of resubmissions'),
 (2025,'Snapshot National Loan-Level','2026-06-02','Provisional: appendix only, not in the main series');
