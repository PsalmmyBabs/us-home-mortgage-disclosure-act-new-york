-- =====================================================================
-- 007  Labelled views
--
-- The fact table stores codes. These views join ref.ref_code once so
-- that everyday analysis reads in English. Codes are never overwritten
-- in place: keeping them is what makes an unmapped value detectable.
-- =====================================================================
CREATE OR REPLACE VIEW marts.v_application AS
SELECT f.activity_year,
       f.application_sk,
       d.source_dataset,
       d.is_provisional,
       i.institution_name,
       i.top_holder_name,
       i.is_minority_owned         AS lender_is_minority_owned,
       i.assets_thousands          AS lender_assets_thousands,
       i.cra_rating                AS lender_cra_rating,
       ra.label                    AS action_taken,
       pu.label                    AS loan_purpose,
       lt.label                    AS loan_type,
       ls.label                    AS lien_status,
       oc.label                    AS occupancy_type,
       ap.derived_race             AS applicant_race,
       ap.derived_ethnicity        AS applicant_ethnicity,
       ap.derived_sex              AS applicant_sex,
       ap.applicant_age,
       ap.race_not_reported,
       m.msa_md_name               AS msa_name,
       f.county_code,
       f.census_tract,
       t.minority_population_pct   AS tract_minority_pct,
       t.tract_to_msa_income_pct,
       f.loan_amount,
       f.income_thousands,
       f.property_value,
       f.interest_rate,
       f.rate_spread,
       f.loan_to_value_ratio,
       f.debt_to_income_band,
       f.total_loan_costs,
       f.is_exempt_filer,
       f.income_na_reason,
       f.ltv_na_reason,
       (f.action_taken IN ('1','3'))            AS is_decided,
       (f.action_taken = '3')                   AS is_denied,
       (f.action_taken = '1')                   AS is_originated,
       (f.action_taken = '5')                   AS is_closed_incomplete,
       (f.action_taken = '4')                   AS is_withdrawn,
       (f.action_taken = '6')                   AS is_purchased_loan
FROM marts.fct_application f
JOIN marts.dim_date              d  ON d.activity_year = f.activity_year
JOIN marts.dim_institution       i  ON i.activity_year = f.activity_year AND i.lei = f.lei
JOIN marts.dim_tract             t  ON t.activity_year = f.activity_year AND t.census_tract = f.census_tract
JOIN marts.dim_msa               m  ON m.activity_year = f.activity_year AND m.msa_md = f.msa_md
JOIN marts.dim_loan_product      p  ON p.loan_product_sk = f.loan_product_sk
JOIN marts.dim_dwelling          w  ON w.dwelling_sk = f.dwelling_sk
JOIN marts.dim_applicant_profile ap ON ap.applicant_profile_sk = f.applicant_profile_sk
JOIN ref.ref_code ra ON ra.code_field='action_taken'   AND ra.code_value = f.action_taken
JOIN ref.ref_code pu ON pu.code_field='loan_purpose'   AND pu.code_value = p.loan_purpose
JOIN ref.ref_code lt ON lt.code_field='loan_type'      AND lt.code_value = p.loan_type
JOIN ref.ref_code ls ON ls.code_field='lien_status'    AND ls.code_value = p.lien_status
JOIN ref.ref_code oc ON oc.code_field='occupancy_type' AND oc.code_value = w.occupancy_type;

-- Denial reasons, one row per reason, in words.
CREATE OR REPLACE VIEW marts.v_denial_reason AS
SELECT b.activity_year, b.application_sk, b.reason_ordinal, r.label AS denial_reason
FROM marts.br_denial_reason b
LEFT JOIN ref.ref_code r ON r.code_field='denial_reason_1' AND r.code_value = b.denial_reason_code;

-- Applicant-reported races, one row per reported race, in words.
CREATE OR REPLACE VIEW marts.v_application_race AS
SELECT b.activity_year, b.application_sk, b.party, b.slot, r.label AS race
FROM marts.br_application_race b
LEFT JOIN ref.ref_code r ON r.code_field='applicant_race_1' AND r.code_value = b.race_code;
