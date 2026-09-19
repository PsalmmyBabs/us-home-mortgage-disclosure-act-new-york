# Phase 05: Building the objects

The DDL, and the reasoning behind each choice. Fifteen tables, five views, 62 foreign keys, 25 check constraints, 12 indexes.

Previous phase: [04 Designing the data model](04_data_model.md) · Next phase: [06 Transforming raw into the model](06_transforming_raw_into_the_model.md)

---

## 1. Order of execution

| file | what it creates | time |
|---|---|---|
| `001_schemas.sql` | the three schemas and three helper functions | instant |
| `002b_ref_code_seed.sql` | 450 code-to-label mappings | instant |
| `002_dimensions.sql` | the eight dimensions | 7 sec |
| `003_fact.sql` | the partitioned fact table | **6 min 18 sec** |
| `004_bridges.sql` | the four bridge tables | 36 sec |
| `005_constraints_indexes.sql` | keys, foreign keys, indexes | 23 sec |
| `006_quarantine_and_checks.sql` | domain rules and the quarantine table | 6 sec |
| `007_views.sql` | three labelled views | instant |
| `008_assertions.sql` | the assertion framework and its two views | instant |

Total about eight minutes. Every file drops and recreates only what it owns, so the sequence is re-runnable from the top.

Final footprint: `marts` 2,638 MB, `raw` 708 MB, `ref` 264 kB.

---

## 2. Three schemas, and why

```sql
CREATE SCHEMA raw;    -- as received, never edited
CREATE SCHEMA ref;    -- reference data and metadata
CREATE SCHEMA marts;  -- the model
```

A reviewer can tell at a glance which layer they are looking at, and the layering is enforced by convention that is visible in every query. `raw` is immutable evidence. `ref` is what codes mean and where data came from. `marts` is interpretation.

---

## 3. Three helper functions, because the same decision recurs 20 times

HMDA writes "no value" five different ways in otherwise numeric columns. Rather than repeating a `CASE` expression on every cast, the rule is written once.

```sql
CREATE FUNCTION ref.to_num(v text) RETURNS numeric
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN v IS NULL OR btrim(v) = '' THEN NULL
              WHEN btrim(v) IN ('NA','Exempt','1111','8888','9999') THEN NULL
              WHEN btrim(v) ~ '^-?[0-9]+(\.[0-9]+)?$' THEN btrim(v)::numeric
              ELSE NULL END
$$;
```

`ref.na_reason(v)` is its mirror: it returns *why* a value became NULL, so the distinction between "not applicable", "exempt filer" and "no co-applicant" survives the cast.

`ref.repair_county(county, tract)` recovers a missing county from the first five characters of an 11-digit tract code, which is the county FIPS by construction.

All three are `IMMUTABLE` and `PARALLEL SAFE`, which lets the planner use parallel workers on the fact build and lets the functions appear in index expressions if needed later.

---

## 4. Dimensions

### 4.1 Grain, decided by measurement

Geography and institution dimensions are keyed on `(natural_key, activity_year)` because their attributes genuinely move. Phase 04 section 3.3 has the evidence: 5,064 of 5,282 tracts differ across years, 2,367 institutions change name or parent, and zero tract-years conflict internally.

```sql
ALTER TABLE marts.dim_tract       ADD PRIMARY KEY (activity_year, census_tract);
ALTER TABLE marts.dim_institution ADD PRIMARY KEY (activity_year, lei);
ALTER TABLE marts.dim_county      ADD PRIMARY KEY (activity_year, county_code);
ALTER TABLE marts.dim_msa         ADD PRIMARY KEY (activity_year, msa_md);
```

This is a year-keyed dimension rather than a full Type 2 with validity ranges. That is a deliberate simplification: the data arrives one discrete year at a time, so a year key expresses the same information with a simpler join and no date-range predicates.

### 4.2 Unknown members, so nothing is silently dropped

16,059 applications have no census tract and 13,345 have no county even after repair. Dropping them would lose 0.9 percent of the data and quietly bias anything geographic. Instead each geography dimension carries an explicit `UNKNOWN` row per year:

```sql
INSERT INTO marts.dim_tract (activity_year, census_tract, county_code)
SELECT d.activity_year, 'UNKNOWN', 'UNKNOWN' FROM marts.dim_date d;
```

The fact then joins successfully for every row, the foreign key holds, and an analyst filtering to `census_tract <> 'UNKNOWN'` is making a visible choice rather than inheriting an invisible one.

### 4.3 Junk dimensions, because eleven codes have 235 real combinations

Seven coded columns describe the loan product and four describe the property. Across 1.75 million rows they take only **194** and **41** distinct combinations respectively.

```sql
CREATE TABLE marts.dim_loan_product AS
SELECT row_number() OVER (ORDER BY loan_type, loan_purpose, lien_status,
                                   derived_loan_product_type, reverse_mortgage,
                                   open_end_line_of_credit,
                                   business_or_commercial_purpose)::int AS loan_product_sk, *
FROM (SELECT DISTINCT loan_type, loan_purpose, lien_status, derived_loan_product_type,
             reverse_mortgage, open_end_line_of_credit, business_or_commercial_purpose
      FROM raw.raw_lar) c;
```

The surrogate key comes from `row_number()` over an explicit `ORDER BY` rather than an identity column, so a rebuild produces the same keys. That is the same reproducibility principle as the fact table's key, applied to the dimensions.

### 4.4 Flags computed once instead of in every query

`dim_applicant_profile` carries `race_not_reported`, `ethnicity_not_reported`, `sex_not_reported` and `has_no_co_applicant` as booleans. Every one is derivable, and deriving it in fifty different analysis queries is fifty chances to define it differently.

---

## 5. The fact table

### 5.1 Partitioned by filing year

```sql
CREATE TABLE marts.fct_application ( ... ) PARTITION BY LIST (activity_year);
CREATE TABLE marts.fct_application_2022 PARTITION OF marts.fct_application FOR VALUES IN (2022);
-- and 2023, 2024, 2025
```

| partition | rows | size |
|---|---|---|
| 2022 | 549,538 | 211 MB |
| 2023 | 391,412 | 151 MB |
| 2024 | 383,447 | 148 MB |
| 2025 | 430,449 | 166 MB |

List partitioning rather than range, because the partition key is a discrete year with four known values, not a continuous timestamp. Three things follow. Nearly every query filters by year, so the planner prunes to one partition. A new year is `CREATE TABLE ... PARTITION OF` and a load, with no rebuild. And the provisional 2025 data is physically separable, so excluding it from the trend series is a partition-level decision rather than a `WHERE` clause everyone has to remember.

A partitioned table's primary key must contain the partition key, so:

```sql
ALTER TABLE marts.fct_application ADD PRIMARY KEY (activity_year, application_sk);
```

### 5.2 Columns that record how a value came to be

Beyond the keys and measures, the fact carries four `*_na_reason` columns plus two provenance flags:

| column | rows set | meaning |
|---|---|---|
| `is_exempt_filer` | 48,131 | this filer uses the partial reporting exemption |
| `county_was_repaired` | 236 | the county code was derived from the tract code, not reported |

Neither is in the source. Both answer a question a reviewer will ask, and answering it in a column beats answering it in a paragraph.

---

## 6. Constraints, declared after the load

62 foreign keys, 25 check constraints, 17 primary keys, 5 unique constraints.

They are added in `005` and `006`, after the bulk insert, so the load is not validated row by row. But they are added. An undeclared model is an unverified one, and a foreign key that exists in a diagram but not in the catalogue is documentation, not integrity.

```sql
ALTER TABLE marts.fct_application
  ADD CONSTRAINT fk_fct_institution FOREIGN KEY (activity_year, lei)
      REFERENCES marts.dim_institution (activity_year, lei),
  ADD CONSTRAINT fk_fct_tract FOREIGN KEY (activity_year, census_tract)
      REFERENCES marts.dim_tract (activity_year, census_tract);
```

The check constraints encode things that cannot be true. `action_taken` must be one of eight codes. `loan_amount` must be positive. `interest_rate` must be between 0 and 50. `loan_to_value_ratio` must be between 0 and 300. Phase 06 explains what happens to the rows that fail them.

Bridge tables reference the fact with `ON DELETE CASCADE`, so removing an application cannot leave orphaned race or denial rows behind.

---

## 7. Indexes, chosen from the predicates the analysis actually uses

Twelve indexes, not one per column.

```sql
-- nearly every fairness query filters to decided applications, so this is partial.
-- action_taken is in the key as well as the predicate: see phase 09 section 4.
CREATE INDEX idx_fct_decided ON marts.fct_application
  (activity_year, applicant_profile_sk, action_taken)
  WHERE action_taken IN ('1','3');

CREATE INDEX idx_fct_lender_tract ON marts.fct_application (lei, census_tract);
CREATE INDEX idx_fct_tract        ON marts.fct_application (activity_year, census_tract);
CREATE INDEX idx_fct_product      ON marts.fct_application (loan_product_sk);
CREATE INDEX idx_fct_action       ON marts.fct_application (action_taken);
CREATE INDEX idx_br_race_code     ON marts.br_application_race (race_code) WHERE party = 'applicant';
```

**Why `idx_fct_decided` is partial.** Denial rate is `denied / (originated + denied)`, so almost every analysis query carries `action_taken IN ('1','3')`. Indexing only those rows makes the index about 70 percent of the size of a full one and lets the planner use an index-only scan. Verified on the 2024 partition: 282,039 index entries against 383,447 rows.

The first version of this index stopped at two columns, and phase 09 shows the planner ignored it entirely. `action_taken` had to be added to the key, not just the predicate. Phase 09 section 4 has the plans.

**Why `idx_fct_lender_tract` is `(lei, census_tract)` in that order.** The lender-versus-market analysis groups by tract within lender, so `lei` leads. Reversing the columns would serve a different question and is the kind of choice worth stating rather than leaving to the reader.

### 7.1 An honest cost

The 2024 partition is 148 MB in total: 91 MB of heap and 57 MB of indexes. Indexes are 63 percent of the size of the data they sit on, which is high, and the reason is one index:

| index | size |
|---|---|
| `activity_year_row_hash_dup_seq_key` | 25 MB |
| `pkey` | 12 MB |
| `lei_census_tract_idx` | 11 MB |
| the other four | about 9 MB combined |

The 25 MB is the price of the reproducible key, because it indexes a 32 character md5 string. Across four partitions that is roughly 114 MB to guarantee that a rebuild produces identical keys. Phase 09 measures the `bigint` alternative rather than estimating it: 12 MB against 25 MB, a 52 percent saving.

---

## 8. Views, so codes read as English

Codes are stored as codes, deliberately. The views do the joining once so that nobody writing analysis has to.

```sql
CREATE VIEW marts.v_application AS
SELECT f.activity_year, f.application_sk,
       i.institution_name, i.is_minority_owned AS lender_is_minority_owned,
       ra.label AS action_taken, pu.label AS loan_purpose,
       ap.derived_race AS applicant_race,
       t.minority_population_pct AS tract_minority_pct,
       f.loan_amount, f.income_thousands, f.rate_spread,
       (f.action_taken IN ('1','3')) AS is_decided,
       (f.action_taken = '3')        AS is_denied,
       (f.action_taken = '1')        AS is_originated,
       (f.action_taken = '5')        AS is_closed_incomplete
FROM marts.fct_application f
JOIN marts.dim_institution i ON i.activity_year = f.activity_year AND i.lei = f.lei
JOIN ref.ref_code ra ON ra.code_field = 'action_taken' AND ra.code_value = f.action_taken
-- and the remaining dimensions and code joins
;
```

The boolean flags matter more than they look. `is_denied` and `is_decided` mean the denominator of a denial rate is defined in exactly one place. Without them, every analyst writes their own, and sooner or later one of them includes purchased loans, which have no decision attached, and reports a number that is wrong by a third.

`v_denial_reason` and `v_application_race` do the same for the bridges.

---

## 9. What is worth defending in a review

| choice | the alternative | why this one |
|---|---|---|
| Year-keyed dimensions | one row per tract | 5,064 of 5,282 tracts vary across years |
| List partitioning by year | no partitioning | queries filter by year; the provisional year is separable |
| Codes kept, views for labels | overwrite codes with text | an unmapped code stays detectable |
| Constraints after the load | during, or not at all | fast load, and still verified |
| Partial index on decided rows | full index | 70 percent of the size, serves the dominant predicate |
| `row_number()` surrogate keys | identity columns | a rebuild produces identical keys |
| Explicit `UNKNOWN` members | drop rows without geography | keeps 0.9 percent of the data and makes exclusion a visible choice |
