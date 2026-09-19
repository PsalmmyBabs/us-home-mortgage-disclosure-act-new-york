-- =====================================================================
-- 009  Documentation, stored in the database
--
-- A data dictionary that lives in a wiki drifts from the schema within a
-- quarter. These comments live in the catalogue, so they are versioned with
-- the DDL, visible in pgAdmin and psql (\d+), and queryable:
--
--   SELECT col_description('marts.fct_application'::regclass, 12);
--
-- docs/catalog is generated from exactly this, so the published data
-- dictionary cannot describe a column that no longer exists.
--
-- Where a comment explains WHY rather than WHAT, it names the phase
-- document that has the evidence.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Schemas
-- ---------------------------------------------------------------------
COMMENT ON SCHEMA raw   IS 'As received from the publisher. Every column is text, nothing is cast, cleaned or interpreted, and nothing is ever edited. Phase 03.';
COMMENT ON SCHEMA ref   IS 'Reference data and provenance: what the codes mean, which dataset vintage each year came from, and what the build asserts.';
COMMENT ON SCHEMA marts IS 'The dimensional model. Interpretation lives here, and every interpretation is reversible because raw is untouched.';

-- ---------------------------------------------------------------------
-- Fact
-- ---------------------------------------------------------------------
COMMENT ON TABLE marts.fct_application IS
  'One row per mortgage application, 1,754,846 rows, LIST partitioned by activity_year. Grain: one filed application as published. HMDA has no natural key, so the business key is (row_hash, dup_seq). Phase 06.';

COMMENT ON COLUMN marts.fct_application.activity_year IS 'Filing year, and the partition key. 2025 is a provisional vintage: see marts.dim_date.is_provisional.';
COMMENT ON COLUMN marts.fct_application.application_sk IS 'Surrogate key, a compact bigint derived from the deterministic ordering of (row_hash, dup_seq). Stable across rebuilds.';
COMMENT ON COLUMN marts.fct_application.row_hash IS 'md5 of the entire published source row. The Bureau strips every loan identifier, so this is the only content-derived identity available. Phase 06 section 3.';
COMMENT ON COLUMN marts.fct_application.dup_seq IS 'Occurrence number within row_hash. 2,081 hash groups contain byte-identical rows, the largest holding 77. Whether those are real duplicate applications cannot be determined from the data, so they are numbered rather than deduplicated.';
COMMENT ON COLUMN marts.fct_application.lei IS 'Legal Entity Identifier of the filing institution. Joins marts.dim_institution on (activity_year, lei).';
COMMENT ON COLUMN marts.fct_application.census_tract IS 'Eleven digit census tract, or the literal UNKNOWN for the 16,059 applications with none. Never NULL, so the foreign key holds and no row is silently dropped.';
COMMENT ON COLUMN marts.fct_application.county_code IS 'Five digit county FIPS, UNKNOWN where absent. 236 rows were recovered from the tract code: see county_was_repaired.';
COMMENT ON COLUMN marts.fct_application.msa_md IS 'Metropolitan Statistical Area or Division, UNKNOWN where absent.';
COMMENT ON COLUMN marts.fct_application.loan_product_sk IS 'Junk dimension key. Seven product codes take only 194 real combinations across 1.75 million rows.';
COMMENT ON COLUMN marts.fct_application.dwelling_sk IS 'Junk dimension key for the four property attributes, 41 real combinations.';
COMMENT ON COLUMN marts.fct_application.applicant_profile_sk IS 'Applicant demographic combination. For individual reported races use marts.br_application_race, because derived_race collapses multi-race applicants into one bucket.';
COMMENT ON COLUMN marts.fct_application.action_taken IS 'Outcome code, 1 to 8. Only 1 (originated) and 3 (denied) are credit decisions, so a denial rate is denied / (originated + denied) and nothing else. Phase 08 section 1.';
COMMENT ON COLUMN marts.fct_application.purchaser_type IS 'Who the loan was sold to, where it was. A non-zero value implies the loan was originated.';
COMMENT ON COLUMN marts.fct_application.preapproval IS 'Whether a preapproval was requested.';
COMMENT ON COLUMN marts.fct_application.loan_amount IS 'Loan amount in dollars, rounded by the publisher to the nearest ten thousand. That rounding is why the first-digit distribution over-represents 5. Phase 02 section 2.1.';
COMMENT ON COLUMN marts.fct_application.income_thousands IS 'Gross annual applicant income in thousands of dollars. Absent on 210,938 rows: see income_na_reason.';
COMMENT ON COLUMN marts.fct_application.property_value IS 'Property value in dollars, rounded by the publisher.';
COMMENT ON COLUMN marts.fct_application.interest_rate IS 'Interest rate as a percentage. Exists only for originated loans, so 36 percent of rows are NULL by the shape of the process rather than by data loss.';
COMMENT ON COLUMN marts.fct_application.rate_spread IS 'Difference between the APR and the comparable benchmark rate. Present only where the loan priced above the reporting threshold, so a pricing analysis is a conditional comparison on a selected group.';
COMMENT ON COLUMN marts.fct_application.loan_to_value_ratio IS 'LTV as a percentage. Values above 300 are impossible and were quarantined, the largest being 86,496,900.';
COMMENT ON COLUMN marts.fct_application.debt_to_income_band IS 'Debt to income, stored as text because the publisher reports it two ways: a plain number only in the range 36 to 49, and a coarsened band such as 20%-<30% elsewhere. Phase 06 section 2.2.';
COMMENT ON COLUMN marts.fct_application.total_loan_costs IS 'Total loan costs in dollars, originated loans only.';
COMMENT ON COLUMN marts.fct_application.total_points_and_fees IS 'Total points and fees in dollars.';
COMMENT ON COLUMN marts.fct_application.origination_charges IS 'Lender origination charges in dollars.';
COMMENT ON COLUMN marts.fct_application.discount_points IS 'Discount points paid in dollars.';
COMMENT ON COLUMN marts.fct_application.lender_credits IS 'Lender credits in dollars.';
COMMENT ON COLUMN marts.fct_application.loan_term_months IS 'Scheduled loan term in months.';
COMMENT ON COLUMN marts.fct_application.intro_rate_period IS 'Months until the first rate adjustment, for adjustable products.';
COMMENT ON COLUMN marts.fct_application.multifamily_affordable_units IS 'Income-restricted units, multifamily properties only.';
COMMENT ON COLUMN marts.fct_application.income_na_reason IS 'Why income is NULL: not_applicable, exempt_filer, no_co_applicant. HMDA writes no value five different ways and they do not mean the same thing, so the reason is preserved rather than collapsed.';
COMMENT ON COLUMN marts.fct_application.dti_na_reason IS 'Why debt to income is NULL. Note that band values are labelled unparseable, which is cosmetic noise rather than a data problem.';
COMMENT ON COLUMN marts.fct_application.ltv_na_reason IS 'Why loan to value is NULL.';
COMMENT ON COLUMN marts.fct_application.rate_spread_na_reason IS 'Why rate spread is NULL. 866,365 rows are not_applicable because the loan priced below the reporting threshold.';
COMMENT ON COLUMN marts.fct_application.applicant_credit_score_type IS 'Scoring model used. 80,101 rows carry one of five values the published code list does not define: newer models added to the filing instructions after the documentation page was written. Phase 07 section 5.';
COMMENT ON COLUMN marts.fct_application.co_applicant_credit_score_type IS 'Scoring model used for the co-applicant.';
COMMENT ON COLUMN marts.fct_application.submission_of_application IS 'Whether the application was submitted directly to the institution.';
COMMENT ON COLUMN marts.fct_application.initially_payable_to_institution IS 'Whether the obligation was initially payable to the filing institution.';
COMMENT ON COLUMN marts.fct_application.hoepa_status IS 'High-cost mortgage status under HOEPA.';
COMMENT ON COLUMN marts.fct_application.conforming_loan_limit IS 'Whether the loan amount is within the conforming limit.';
COMMENT ON COLUMN marts.fct_application.is_exempt_filer IS 'True where the institution used the partial reporting exemption, 48,131 rows. These withhold the same fields on every application, so they are a coherent cohort rather than scattered nulls.';
COMMENT ON COLUMN marts.fct_application.county_was_repaired IS 'True where the county was derived from the first five digits of the census tract rather than reported, 236 rows. Recorded so that derived geography can be excluded with one predicate.';

COMMENT ON TABLE marts.quarantine_application IS
  'The 573 rows that could not be true: one interest rate of 450.0 and 572 loan-to-value ratios above 300. Same structure as the fact plus the rule broken and when it was detected. They are moved here rather than deleted, so the model can state what it refused and why. Phase 06 section 2.3.';
COMMENT ON COLUMN marts.quarantine_application.violated_rule IS 'Which domain rule the row broke: interest_rate_not_a_percentage, ltv_not_a_ratio or loan_amount_not_positive.';
COMMENT ON COLUMN marts.quarantine_application.detected_at IS 'When the row was quarantined. The step is idempotent, so re-running the build finds nothing new.';

-- ---------------------------------------------------------------------
-- Dimensions
-- ---------------------------------------------------------------------
COMMENT ON TABLE marts.dim_date IS 'One row per filing year, carrying the publication vintage. A four-year comparison mixes vintages, so provenance is queryable rather than living in a comment. Phase 01 section 4.';
COMMENT ON COLUMN marts.dim_date.source_dataset IS 'Which CFPB publication the year came from: Snapshot, One Year or Three Year National Loan-Level.';
COMMENT ON COLUMN marts.dim_date.source_freeze_date IS 'The date the publisher froze that dataset. Later resubmissions are not included.';
COMMENT ON COLUMN marts.dim_date.is_provisional IS 'True for 2025, a Snapshot taken one month after the filing deadline. Excluded from every trend claim.';

COMMENT ON TABLE marts.dim_institution IS 'One row per lender per year, 756 to 802 lenders each year. Year-keyed because 2,367 institutions change name or parent across the window. Combines the CFPB transmittal sheet with the Philadelphia Fed lender file.';
COMMENT ON COLUMN marts.dim_institution.lei IS 'Legal Entity Identifier, the institution key within a year.';
COMMENT ON COLUMN marts.dim_institution.institution_name IS 'Filing institution name. Four rows carry the Unicode replacement character, from an encoding fault in the publisher''s own file, and are left as published.';
COMMENT ON COLUMN marts.dim_institution.agency_code IS 'Which regulator the institution files with.';
COMMENT ON COLUMN marts.dim_institution.national_lar_count IS 'Applications the institution filed nationally that year. Useful for judging how much of a lender this state sees.';
COMMENT ON COLUMN marts.dim_institution.top_holder_rssd IS 'RSSD identifier of the ultimate holding company, so subsidiaries of one group can be rolled up.';
COMMENT ON COLUMN marts.dim_institution.assets_thousands IS 'Total assets in thousands of dollars, which allows a lender to be compared with genuine size peers rather than the whole market.';
COMMENT ON COLUMN marts.dim_institution.cra_rating IS 'Community Reinvestment Act examination rating, an independent regulatory assessment to set beside any disparity measured here.';
COMMENT ON COLUMN marts.dim_institution.is_minority_owned IS 'Minority-owned institution flag from the Philadelphia Fed file.';

COMMENT ON TABLE marts.dim_tract IS 'One row per census tract per year, about 5,200 tracts. Year-keyed from measurement: 5,064 of 5,282 tracts differ across years, and zero tract-years conflict internally. Carries an explicit UNKNOWN member per year.';
COMMENT ON COLUMN marts.dim_tract.minority_population_pct IS 'Minority share of the tract population. Denial rises from 21.7 percent in tracts under 20 percent minority to 37.2 percent at 80 percent and above.';
COMMENT ON COLUMN marts.dim_tract.tract_to_msa_income_pct IS 'Tract median family income as a percentage of its metropolitan area, the standard measure of relative neighbourhood affluence.';

COMMENT ON TABLE marts.dim_county IS 'One row per county per year, 63 New York counties, with the metropolitan area it belongs to.';
COMMENT ON TABLE marts.dim_msa IS 'One row per metropolitan area per year, 15 in New York, with its published name.';

COMMENT ON TABLE marts.dim_loan_product IS 'Junk dimension: the 194 combinations that seven loan product codes actually take. Keys are row_number over an explicit ORDER BY rather than an identity column, so a rebuild produces the same keys.';
COMMENT ON COLUMN marts.dim_loan_product.loan_purpose IS 'Home purchase, refinancing, cash-out refinancing, home improvement or other. Home improvement is the second largest product here and denies at 41.5 percent overall.';
COMMENT ON COLUMN marts.dim_loan_product.lien_status IS 'First or subordinate lien.';

COMMENT ON TABLE marts.dim_dwelling IS 'Junk dimension: the 41 combinations of the four property attributes.';
COMMENT ON TABLE marts.dim_applicant_profile IS 'Distinct applicant demographic combinations, with four derived flags so that not-reported is defined once rather than in every analysis query.';
COMMENT ON COLUMN marts.dim_applicant_profile.derived_race IS 'The publisher''s single-valued race. It collapses anyone reporting two or more races into one bucket, so multi-race applicants vanish from every individual group. Use marts.br_application_race for reported races.';
COMMENT ON COLUMN marts.dim_applicant_profile.co_applicant_age IS 'Age band of the co-applicant. The sentinel 9999 means there is no co-applicant, which is a fact about 989,860 applications rather than an absence.';
COMMENT ON COLUMN marts.dim_applicant_profile.has_no_co_applicant IS 'Derived from the 9999 sentinel, so that a single-applicant filter is written once.';

-- ---------------------------------------------------------------------
-- Bridges
-- ---------------------------------------------------------------------
COMMENT ON TABLE marts.br_application_race IS
  'One row per reported race per party per application, 3,662,829 rows. The source publishes five numbered columns per party, which is a first normal form violation. Codes are hierarchical: 2 is Asian and 22 is Chinese, so subcategories must be rolled to their parent before counting distinct races. Not doing so overstates multi-race applicants by a factor of six, 106,971 against 18,051. Phase 06 section 4.1.';
COMMENT ON COLUMN marts.br_application_race.party IS 'applicant or co_applicant.';
COMMENT ON COLUMN marts.br_application_race.slot IS 'Which of the five numbered source columns this came from. Kept so the unpivot is reversible.';
COMMENT ON COLUMN marts.br_application_race.race_code IS 'Reported race code. Roll to the top level with left(race_code,1) before counting distinct races.';

COMMENT ON TABLE marts.br_application_ethnicity IS 'One row per reported ethnicity per party per application, 3,597,440 rows. Same hierarchical structure as race.';
COMMENT ON TABLE marts.br_denial_reason IS
  'One row per denial reason, 438,591 rows. Code 10, not applicable, is excluded at build time so that no row asserts a reason where none was given. 27,229 applications carry a reason where the outcome was not a denial, 21,665 of them on originated loans: a filer system defect, reported rather than corrected. Always filter to actual denials.';
COMMENT ON TABLE marts.br_underwriting_system IS 'One row per automated underwriting system consulted, 1,075,534 rows. Code 6, not applicable, is excluded at build time.';

-- ---------------------------------------------------------------------
-- Reference and provenance
-- ---------------------------------------------------------------------
COMMENT ON TABLE ref.ref_code IS 'Code to label mappings, 450 rows across 54 columns. Codes are stored as codes in the model and labelled here, so an undocumented code stays detectable instead of being silently overwritten with text.';
COMMENT ON TABLE ref.ref_source_vintage IS 'Which published dataset and freeze date each filing year came from. The only table in the raw layer containing anything not lifted from a file.';
COMMENT ON TABLE ref.assertion_catalog IS
  'The eight build assertions and their severity. build_error must be zero. source_defect is a real problem in the filed data that this repository has no standing to correct, so it carries a documented tolerance and fails only if it worsens. Phase 07 section 2.';
COMMENT ON COLUMN ref.assertion_catalog.tolerance IS 'Maximum acceptable share of rows, source defects only. The denial-reason contradiction sits at 1.55 percent against a 2 percent tolerance.';

-- ---------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------
COMMENT ON VIEW marts.v_application IS 'The fact with every code resolved to its label, plus is_decided, is_denied, is_originated and is_closed_incomplete. Those booleans mean the denominator of a denial rate is defined in exactly one place.';
COMMENT ON VIEW marts.v_denial_reason IS 'Denial reasons with labels and an is_denied flag. Filter on is_denied: without it the top reasons are contaminated by 21,665 loans that were approved and funded.';
COMMENT ON VIEW marts.v_application_race IS 'Reported races with labels and a race_top_level column, so the hierarchy rollup does not have to be rewritten by every analyst.';
COMMENT ON VIEW marts.assert_results IS 'All eight assertions with their current counts, tolerances and status. Run this after any build.';
COMMENT ON VIEW marts.assert_failures IS 'The CI gate. Returns rows only when a build_error is non-zero or a source_defect has exceeded its tolerance.';

ANALYZE;

-- ---------------------------------------------------------------------
-- Remaining columns
-- ---------------------------------------------------------------------
COMMENT ON COLUMN marts.br_application_ethnicity.ethnicity_code IS 'Reported ethnicity code. Hierarchical like race: roll to the top level before counting distinct ethnicities.';
COMMENT ON COLUMN marts.br_denial_reason.reason_ordinal IS 'Which of the four numbered denial reason columns this came from. Filers are not required to rank them, so ordinal 1 is not necessarily the primary reason.';
COMMENT ON COLUMN marts.br_denial_reason.denial_reason_code IS 'Reason code. Code 10, not applicable, is excluded at build time so no row claims a reason where none was given.';
COMMENT ON COLUMN marts.br_underwriting_system.aus_ordinal IS 'Which of the five numbered AUS columns this came from.';
COMMENT ON COLUMN marts.br_underwriting_system.aus_code IS 'Automated underwriting system consulted. Code 6, not applicable, is excluded at build time.';

COMMENT ON COLUMN marts.dim_applicant_profile.applicant_profile_sk IS 'Surrogate key from row_number over an explicit ORDER BY, so a rebuild produces the same keys.';
COMMENT ON COLUMN marts.dim_applicant_profile.derived_ethnicity IS 'The publisher''s single-valued ethnicity. Use marts.br_application_ethnicity for what was actually reported.';
COMMENT ON COLUMN marts.dim_applicant_profile.derived_sex IS 'The publisher''s single-valued sex, including Joint and Sex Not Available.';
COMMENT ON COLUMN marts.dim_applicant_profile.applicant_age IS 'Age band. The sentinel 8888 means not applicable, on 194,303 applications.';
COMMENT ON COLUMN marts.dim_applicant_profile.race_not_reported IS 'Derived flag. Race is unreported on 24.5 percent of applications, which bounds every group comparison in the analysis.';
COMMENT ON COLUMN marts.dim_applicant_profile.ethnicity_not_reported IS 'Derived flag, 23.2 percent of applications.';
COMMENT ON COLUMN marts.dim_applicant_profile.sex_not_reported IS 'Derived flag, 16.5 percent of applications.';

COMMENT ON COLUMN marts.dim_date.vintage_note IS 'Plain language note on what the vintage means for comparability.';

COMMENT ON COLUMN marts.dim_dwelling.dwelling_sk IS 'Surrogate key from row_number over an explicit ORDER BY.';
COMMENT ON COLUMN marts.dim_dwelling.derived_dwelling_category IS 'Single family or multifamily, site built or manufactured.';
COMMENT ON COLUMN marts.dim_dwelling.construction_method IS 'Site built or manufactured home.';
COMMENT ON COLUMN marts.dim_dwelling.total_units IS 'Units in the property, banded by the publisher above four.';
COMMENT ON COLUMN marts.dim_dwelling.occupancy_type IS 'Principal residence, second residence or investment property.';

COMMENT ON COLUMN marts.dim_institution.institution_city IS 'City of the filing institution as reported on the transmittal sheet.';
COMMENT ON COLUMN marts.dim_institution.institution_state IS 'State of the filing institution, which is where it files from rather than where it lends.';
COMMENT ON COLUMN marts.dim_institution.top_holder_name IS 'Ultimate holding company name, from the Philadelphia Fed lender file.';
COMMENT ON COLUMN marts.dim_institution.parent_name IS 'Immediate parent, which may differ from the top holder in a multi-level group.';
COMMENT ON COLUMN marts.dim_institution.parent_rssd IS 'RSSD identifier of the immediate parent.';
COMMENT ON COLUMN marts.dim_institution.parent_lei IS 'Legal Entity Identifier of the immediate parent, where it has one.';
COMMENT ON COLUMN marts.dim_institution.cra_exam_date IS 'Date of the CRA examination that produced cra_rating. Ratings can be several years old.';

COMMENT ON COLUMN marts.dim_loan_product.loan_product_sk IS 'Surrogate key from row_number over an explicit ORDER BY.';
COMMENT ON COLUMN marts.dim_loan_product.loan_type IS 'Conventional, FHA, VA or USDA.';
COMMENT ON COLUMN marts.dim_loan_product.derived_loan_product_type IS 'The publisher''s combination of loan type and lien status.';
COMMENT ON COLUMN marts.dim_loan_product.reverse_mortgage IS 'Whether the loan is a reverse mortgage.';
COMMENT ON COLUMN marts.dim_loan_product.open_end_line_of_credit IS 'Whether the loan is an open-end line of credit rather than a closed-end mortgage.';
COMMENT ON COLUMN marts.dim_loan_product.business_or_commercial_purpose IS 'Whether the loan is primarily for a business or commercial purpose.';

COMMENT ON COLUMN marts.dim_msa.msa_md_name IS 'Published metropolitan area name.';
COMMENT ON COLUMN marts.dim_msa.msa_state IS 'State the metropolitan area is attributed to.';

COMMENT ON COLUMN marts.dim_tract.tract_population IS 'Tract population from the census vintage the publisher used that year.';
COMMENT ON COLUMN marts.dim_tract.msa_median_family_income IS 'Median family income of the tract''s metropolitan area, the denominator behind tract_to_msa_income_pct.';
COMMENT ON COLUMN marts.dim_tract.owner_occupied_units IS 'Owner-occupied housing units in the tract.';
COMMENT ON COLUMN marts.dim_tract.one_to_four_family_homes IS 'One to four family homes in the tract, the housing stock most HMDA lending is secured on.';
COMMENT ON COLUMN marts.dim_tract.median_age_of_housing IS 'Median age of housing units, a proxy for stock condition and therefore for home improvement demand.';

COMMENT ON COLUMN ref.ref_source_vintage.dataset IS 'Snapshot, One Year or Three Year National Loan-Level.';
COMMENT ON COLUMN ref.ref_source_vintage.freeze_date IS 'When the publisher froze the dataset. Resubmissions after this date are not included.';
COMMENT ON COLUMN ref.ref_source_vintage.note IS 'What the vintage means for comparing this year with the others.';

-- ---------------------------------------------------------------------
-- Structural columns, commented once rather than 40 times
--
-- activity_year means the same thing in every table it appears in, so
-- writing the sentence fourteen times invites fourteen slightly different
-- sentences. These defaults are applied only where no specific comment has
-- already been set above, so a table-specific description always wins.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  r record;
  generic text;
BEGIN
  FOR r IN
    SELECT n.nspname, c.relname, a.attname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    WHERE n.nspname IN ('marts','ref') AND c.relkind IN ('r','p')
      AND col_description(c.oid, a.attnum) IS NULL
  LOOP
    generic := CASE r.attname
      WHEN 'activity_year'        THEN 'Filing year. Part of the key wherever it appears, because the geography and institution dimensions are year-grained.'
      WHEN 'application_sk'       THEN 'Surrogate key of the application. Joins marts.fct_application on (activity_year, application_sk).'
      WHEN 'census_tract'         THEN 'Eleven digit census tract, or the literal UNKNOWN where none was reported.'
      WHEN 'county_code'          THEN 'Five digit county FIPS code, or UNKNOWN.'
      WHEN 'msa_md'               THEN 'Metropolitan Statistical Area or Division code, or UNKNOWN.'
      WHEN 'lei'                  THEN 'Legal Entity Identifier of the filing institution.'
      WHEN 'party'                THEN 'Which party reported this value: applicant or co_applicant.'
      WHEN 'slot'                 THEN 'Which of the numbered source columns this value came from, kept so the unpivot is reversible.'
      WHEN 'code_field'           THEN 'The column the code belongs to.'
      WHEN 'code_value'           THEN 'The code as published, stored as text so leading zeros and non-numeric codes survive.'
      WHEN 'label'                THEN 'The published meaning of the code.'
      WHEN 'state_code'           THEN 'Two letter state code. This build is New York only.'
      WHEN 'assertion'            THEN 'Assertion name, matching marts.assert_results.'
      WHEN 'severity'             THEN 'build_error must be zero. source_defect is a problem in the filed data, tolerated up to a documented share.'
      WHEN 'description'          THEN 'What the assertion checks and, for a source defect, what is known about it.'
      ELSE NULL END;
    IF generic IS NOT NULL THEN
      EXECUTE format('COMMENT ON COLUMN %I.%I.%I IS %L',
                     r.nspname, r.relname, r.attname, generic);
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- The quarantine table is CREATE TABLE ... LIKE the fact, which copies the
-- structure but not the comments. Rather than maintaining 41 duplicates,
-- copy them, so the two can never describe the same column differently.
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT qa.attname, col_description(f.oid, fa.attnum) AS cmt
    FROM pg_class q
    JOIN pg_attribute qa ON qa.attrelid = q.oid AND qa.attnum > 0 AND NOT qa.attisdropped
    JOIN pg_class f ON f.oid = 'marts.fct_application'::regclass
    JOIN pg_attribute fa ON fa.attrelid = f.oid AND fa.attname = qa.attname
    WHERE q.oid = 'marts.quarantine_application'::regclass
      AND col_description(q.oid, qa.attnum) IS NULL
      AND col_description(f.oid, fa.attnum) IS NOT NULL
  LOOP
    EXECUTE format('COMMENT ON COLUMN marts.quarantine_application.%I IS %L',
                   r.attname, r.cmt);
  END LOOP;
END $$;
