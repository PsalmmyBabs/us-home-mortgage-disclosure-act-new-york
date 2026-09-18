-- =====================================================================
-- 002  Dimensions
-- Geography and institution dimensions are grained by activity_year
-- because their attributes genuinely change between filing years:
-- 5,064 of 5,282 census tracts carry different census attributes across
-- the four years, and lender names, parents and CRA ratings all move.
-- Within a single year both are stable (verified: zero tract-years with
-- more than one attribute set, zero with more than one MSA).
-- =====================================================================

-- ---------------------------------------------------------------------
-- dim_date: one row per filing year, carrying the publication vintage
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS marts.dim_date CASCADE;
CREATE TABLE marts.dim_date AS
SELECT v.activity_year,
       v.dataset        AS source_dataset,
       v.freeze_date    AS source_freeze_date,
       v.note           AS vintage_note,
       (v.activity_year = 2025) AS is_provisional
FROM ref.ref_source_vintage v;
ALTER TABLE marts.dim_date ADD PRIMARY KEY (activity_year);

-- ---------------------------------------------------------------------
-- dim_msa
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS marts.dim_msa CASCADE;
CREATE TABLE marts.dim_msa AS
SELECT DISTINCT m.activity_year, m.msa_md, m.msa_md_name, m.state AS msa_state
FROM raw.raw_msamd m
WHERE m.msa_md IS NOT NULL;
INSERT INTO marts.dim_msa
SELECT DISTINCT d.activity_year, 'UNKNOWN', 'Not in an MSA or not reported', NULL
FROM marts.dim_date d;
ALTER TABLE marts.dim_msa ADD PRIMARY KEY (activity_year, msa_md);

-- ---------------------------------------------------------------------
-- dim_county, with county_code repaired from the tract code where absent
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS marts.dim_county CASCADE;
CREATE TABLE marts.dim_county AS
SELECT DISTINCT
       l.activity_year::int                                   AS activity_year,
       ref.repair_county(l.county_code, l.census_tract)        AS county_code,
       coalesce(nullif(l.derived_msa_md,'NA'),'UNKNOWN')       AS msa_md,
       l.state_code
FROM raw.raw_lar l
WHERE ref.repair_county(l.county_code, l.census_tract) IS NOT NULL;
INSERT INTO marts.dim_county
SELECT d.activity_year, 'UNKNOWN', 'UNKNOWN', 'NY' FROM marts.dim_date d;
ALTER TABLE marts.dim_county ADD PRIMARY KEY (activity_year, county_code);

-- ---------------------------------------------------------------------
-- dim_tract: the census attribute layer, one row per tract per year
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS marts.dim_tract CASCADE;
CREATE TABLE marts.dim_tract AS
SELECT DISTINCT
       l.activity_year::int                              AS activity_year,
       l.census_tract,
       ref.repair_county(l.county_code, l.census_tract)  AS county_code,
       ref.to_num(l.tract_population)                    AS tract_population,
       ref.to_num(l.tract_minority_population_percent)   AS minority_population_pct,
       ref.to_num(l.ffiec_msa_md_median_family_income)   AS msa_median_family_income,
       ref.to_num(l.tract_to_msa_income_percentage)      AS tract_to_msa_income_pct,
       ref.to_num(l.tract_owner_occupied_units)          AS owner_occupied_units,
       ref.to_num(l.tract_one_to_four_family_homes)      AS one_to_four_family_homes,
       ref.to_num(l.tract_median_age_of_housing_units)   AS median_age_of_housing
FROM raw.raw_lar l
WHERE l.census_tract <> 'NA';
INSERT INTO marts.dim_tract (activity_year, census_tract, county_code)
SELECT d.activity_year, 'UNKNOWN', 'UNKNOWN' FROM marts.dim_date d;
ALTER TABLE marts.dim_tract ADD PRIMARY KEY (activity_year, census_tract);

-- ---------------------------------------------------------------------
-- dim_institution: transmittal sheet for identity, Avery lender file for
-- ownership, size and CRA. The parent link is what the recursive walk uses.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS marts.dim_institution CASCADE;
CREATE TABLE marts.dim_institution AS
SELECT t.activity_year::int              AS activity_year,
       t.lei,
       t.respondent_name                 AS institution_name,
       t.respondent_city                 AS institution_city,
       t.respondent_state                AS institution_state,
       t.agency_code,
       ref.to_num(t.lar_count)           AS national_lar_count,
       f.namehh                          AS top_holder_name,
       nullif(f.rssdhh,'0')              AS top_holder_rssd,
       f.namep                           AS parent_name,
       nullif(f.rssdp,'0')               AS parent_rssd,
       nullif(f.leir,'')                 AS parent_lei,
       ref.to_num(f.assets)              AS assets_thousands,
       ref.to_num(f.crarate)             AS cra_rating,
       ref.to_num(f.cradate)             AS cra_exam_date,
       (ref.to_num(f.minbnk) IS NOT NULL AND ref.to_num(f.minbnk) > 0) AS is_minority_owned
FROM raw.raw_ts t
LEFT JOIN raw.raw_lender f
       ON f.lei = t.lei AND f.year = t.activity_year;
ALTER TABLE marts.dim_institution ADD PRIMARY KEY (activity_year, lei);

-- ---------------------------------------------------------------------
-- dim_loan_product and dim_dwelling: small junk dimensions collapsing
-- the coded loan and property attributes into labelled combinations
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS marts.dim_loan_product CASCADE;
CREATE TABLE marts.dim_loan_product AS
SELECT row_number() OVER (ORDER BY loan_type, loan_purpose, lien_status,
                                   derived_loan_product_type, reverse_mortgage,
                                   open_end_line_of_credit, business_or_commercial_purpose)::int AS loan_product_sk,
       *
FROM (
  SELECT DISTINCT l.loan_type, l.loan_purpose, l.lien_status,
         l.derived_loan_product_type, l.reverse_mortgage,
         l.open_end_line_of_credit, l.business_or_commercial_purpose
  FROM raw.raw_lar l
) c;
ALTER TABLE marts.dim_loan_product ADD PRIMARY KEY (loan_product_sk);

DROP TABLE IF EXISTS marts.dim_dwelling CASCADE;
CREATE TABLE marts.dim_dwelling AS
SELECT row_number() OVER (ORDER BY derived_dwelling_category, construction_method,
                                   total_units, occupancy_type)::int AS dwelling_sk, *
FROM (
  SELECT DISTINCT l.derived_dwelling_category, l.construction_method,
         l.total_units, l.occupancy_type
  FROM raw.raw_lar l
) c;
ALTER TABLE marts.dim_dwelling ADD PRIMARY KEY (dwelling_sk);

-- ---------------------------------------------------------------------
-- dim_applicant_profile: the derived demographic combination. Credit
-- score type is deliberately excluded (it describes the lender's scoring
-- model, not the applicant) and stays on the fact.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS marts.dim_applicant_profile CASCADE;
CREATE TABLE marts.dim_applicant_profile AS
SELECT row_number() OVER (ORDER BY derived_race, derived_ethnicity, derived_sex,
                                   applicant_age, co_applicant_age)::int AS applicant_profile_sk,
       *,
       (derived_race = 'Race Not Available')            AS race_not_reported,
       (derived_ethnicity = 'Ethnicity Not Available')  AS ethnicity_not_reported,
       (derived_sex = 'Sex Not Available')              AS sex_not_reported,
       (co_applicant_age = '9999')                      AS has_no_co_applicant
FROM (
  SELECT DISTINCT l.derived_race, l.derived_ethnicity, l.derived_sex,
         l.applicant_age, l.co_applicant_age
  FROM raw.raw_lar l
) c;
ALTER TABLE marts.dim_applicant_profile ADD PRIMARY KEY (applicant_profile_sk);
