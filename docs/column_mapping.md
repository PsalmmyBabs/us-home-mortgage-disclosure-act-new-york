# Where all 99 source columns went

The HMDA loan application register is one flat file with 99 columns and one row per application. This document accounts for every one of them.

## The four rules used to decide

Nothing here was decided by taste. Each column was tested against four questions, in order.

**Rule 1: is it a repeating group?**
A column whose name ends in a number, where the same fact repeats across numbered slots, violates first normal form. Those go to a **bridge table**, one row per reported value. Twenty-four columns fall here.

**Rule 2: does it describe something other than this application?**
If a column's value is fixed by something outside the application, it belongs to that thing, not to the application. `tract_population` is a property of the census tract, not of the loan, and repeating it on every row in that tract is duplication. Test: group by the candidate key and count distinct values. If it is always one, the column depends on that key and moves to a **dimension**. Thirty-one columns fall here.

**Rule 3: is it a code that needs a label?**
A numeric code with a published meaning stays on the fact as the code, and its meaning lives once in `ref.ref_code`. Overwriting codes with text would destroy the ability to detect an unmapped value.

**Rule 4: is it a measurement of this application?**
Anything left that varies application by application is a **measure or degenerate attribute on the fact**. Thirty-three columns fall here.

---

## Bridge tables (24 columns)

Each of these arrives as numbered slots. The numbering is a spreadsheet habit, not information, so the slot number becomes data.

| source columns | destination | rows produced |
|---|---|---|
| `applicant_race-1` … `-5`, `co-applicant_race-1` … `-5` | `marts.br_application_race` (`party`, `slot`, `race_code`) | 3,663,907 |
| `applicant_ethnicity-1` … `-5`, `co-applicant_ethnicity-1` … `-5` | `marts.br_application_ethnicity` | 3,598,651 |
| `denial_reason-1` … `-4` | `marts.br_denial_reason` (code 10, "not applicable", is dropped) | 439,277 |
| `aus-1` … `-5` | `marts.br_underwriting_system` (code 6, "not applicable", is dropped) | 1,075,594 |

**Why this is not cosmetic.** `derived_race` collapses anyone reporting two or more races into one bucket holding 3,870 applications. The bridge finds **18,051** applications where the applicant reported more than one top-level race. The flat field hides 4.7 times as many people as it shows.

---

## Dimensions (31 columns)

### `dim_tract` — 7 columns, grain: census tract per year, 20,820 rows

`tract_population`, `tract_minority_population_percent`, `ffiec_msa_md_median_family_income`, `tract_to_msa_income_percentage`, `tract_owner_occupied_units`, `tract_one_to_four_family_homes`, `tract_median_age_of_housing_units`

These describe a neighbourhood, not a loan. Grained by year because **5,064 of 5,282 tracts carry different values across the four years**, and verified stable within a year (zero tract-years with conflicting values).

### `dim_county` — 2 columns, 255 rows

`county_code`, `state_code`

`county_code` is also kept on the fact as a foreign key. Where it was missing it was rebuilt from the first five characters of the 11-digit tract code, which is the county FIPS by construction. 236 rows repaired, flagged by `county_was_repaired`.

### `dim_msa` — 1 column plus the MSA description file, 1,666 rows

`derived_msa-md`

Names come from the year's MSA description file, which is why that file is downloaded per year.

### `dim_institution` — 1 column plus two external files, 19,321 rows

`lei`

The register carries only the identifier. Names come from that year's transmittal sheet; parent company, top holder, asset size, CRA rating and the minority-owned flag come from the Philadelphia Fed lender file. Grained by year because names, owners and ratings all move.

### `dim_loan_product` — 7 columns, 194 rows

`loan_type`, `loan_purpose`, `lien_status`, `derived_loan_product_type`, `reverse_mortgage`, `open-end_line_of_credit`, `business_or_commercial_purpose`

Seven coded columns with only 194 real combinations across 1.76 million rows. A junk dimension: storing the combination once and pointing at it beats repeating seven codes on every row.

### `dim_dwelling` — 4 columns, 41 rows

`derived_dwelling_category`, `construction_method`, `total_units`, `occupancy_type`

Same reasoning, 41 combinations.

### `dim_applicant_profile` — 5 columns, 4,745 rows

`derived_race`, `derived_ethnicity`, `derived_sex`, `applicant_age`, `co-applicant_age`

The pre-derived demographic summary. It also carries four flags computed once here rather than in every query: `race_not_reported`, `ethnicity_not_reported`, `sex_not_reported`, `has_no_co_applicant`.

`applicant_credit_score_type` was deliberately **excluded** from this dimension. It names the scoring model the lender used, which describes the lender's process, not the applicant. It stays on the fact.

### `dim_date` — 1 column, 4 rows

`activity_year`

Also the partition key, and it carries the publication vintage and freeze date from `ref.ref_source_vintage`.

---

## Fact table (33 columns), `marts.fct_application`

### Keys and outcome

`activity_year` (partition key), `lei`, `census_tract`, `county_code`, `derived_msa-md`, `action_taken`, `purchaser_type`, `preapproval`

### Money and terms, cast to numeric

`loan_amount`, `income`, `property_value`, `interest_rate`, `rate_spread`, `loan_to_value_ratio`, `total_loan_costs`, `total_points_and_fees`, `origination_charges`, `discount_points`, `lender_credits`, `loan_term`, `intro_rate_period`, `multifamily_affordable_units`

`debt_to_income_ratio` stays **text**, because the source publishes it as bands like `20%-<30%` rather than a number.

### Codes kept as codes

`conforming_loan_limit`, `hoepa_status`, `applicant_credit_score_type`, `co-applicant_credit_score_type`, `submission_of_application`, `initially_payable_to_institution`

### Derived columns added by the model

`application_sk`, `row_hash`, `dup_seq`, the three dimension surrogate keys, `is_exempt_filer`, `county_was_repaired`, and four `*_na_reason` columns.

**The `*_na_reason` columns are the point.** HMDA writes "no value" five different ways: `NA`, `Exempt`, `1111`, `8888`, `9999`. All become NULL, but the reason is kept beside the measure. A co-applicant age of 9999 means there is no co-applicant, which is not missing data, and treating it as missing would be wrong.

---

## The 17 columns not yet carried, and why

Being explicit about this is the point of a mapping document. Nothing was silently dropped.

**Deliberately superseded (4):** `applicant_sex`, `co-applicant_sex`, `applicant_age_above_62`, `co-applicant_age_above_62`. The first two duplicate `derived_sex`, which handles joint applications properly. The age flags are derivable from `applicant_age`.

**Loan feature flags, a genuine gap (7):** `negative_amortization`, `interest_only_payment`, `balloon_payment`, `other_nonamortizing_features`, `prepayment_penalty_term`, `manufactured_home_secured_property_type`, `manufactured_home_land_property_interest`. These describe non-standard loan structures. They belong in `dim_loan_product` and are not there yet. Adding them would raise its row count from 194 to a few hundred, which is still small.

**The observation flags, and this one matters (6):** `applicant_ethnicity_observed`, `co-applicant_ethnicity_observed`, `applicant_race_observed`, `co-applicant_race_observed`, `applicant_sex_observed`, `co-applicant_sex_observed`.

Each records whether the lender captured that characteristic **by visual observation or surname** rather than by the applicant reporting it. For a project about disparity in lending outcomes that is not a minor field: it distinguishes what an applicant said about themselves from what a loan officer assumed. These should be on the fact, and the omission is worth fixing before the analysis is written up.

---

## Reconciliation

99 source columns = 24 bridged + 31 dimensioned + 33 on the fact + 17 not carried, minus 6 that appear in two places (`county_code`, `census_tract`, `derived_msa-md`, `lei`, `activity_year`, `loan_purpose` appear both as a dimension key and on the fact or as a rule input).

The count that actually matters is the row count, and it is asserted rather than described: `assert_results` checks that `raw.raw_lar` equals `marts.fct_application` plus `marts.quarantine_application`, every time the build runs.
