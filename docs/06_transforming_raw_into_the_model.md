# Phase 06: Transforming raw into the model

How 1,755,419 text rows became a typed, keyed, constrained model, and exactly what happened to every record that had something wrong with it.

Previous phase: [05 Building the objects](05_building_the_objects.md) · Next phase: [07 Quality assertions](07_quality_assertions.md)

---

## 1. The one rule of this phase

Nothing is deleted. Every one of the 1,755,419 published rows is accounted for at the end of the build, and the accounting is a query rather than a claim.

```sql
SELECT (SELECT count(*) FROM raw.raw_lar)                  AS published,
       (SELECT count(*) FROM marts.fct_application)        AS modelled,
       (SELECT count(*) FROM marts.quarantine_application) AS quarantined;
-- 1,755,419 = 1,754,846 + 573
```

| year | published | modelled | quarantined |
|---|---|---|---|
| 2022 | 549,677 | 549,538 | 139 |
| 2023 | 391,574 | 391,412 | 162 |
| 2024 | 383,614 | 383,447 | 167 |
| 2025 | 430,554 | 430,449 | 105 |
| **total** | **1,755,419** | **1,754,846** | **573** |

---

## 2. What happened to records with incomplete or questionable information

This is the question a reviewer should ask first, so it is answered first. Nothing was removed and nothing was deleted. Five different things happen, and which one applies depends on what is actually wrong.

| what is wrong | treatment | rows | still in `raw`? | still in `marts`? |
|---|---|---|---|---|
| A value is missing but recoverable from another column | **repaired**, and the repair is flagged | 236 | yes | yes |
| A value is absent for a documented reason | **absence kept, with the reason recorded** | up to 866,365 per column | yes | yes |
| A value is arithmetically impossible | **quarantined**, with the rule it broke | 573 | yes | moved to quarantine |
| Rows are byte-identical and cannot be told apart | **kept and numbered** | 2,776 excess | yes | yes |
| The filer's submission contradicts itself | **reported, not fixed** | 27,229 | yes | yes |

### 2.1 Repaired: 236 counties

236 applications have no county code but do have a full 11 digit census tract. The first five digits of a census tract are the county FIPS code by construction, so the county is recoverable with certainty rather than guesswork.

```sql
CREATE FUNCTION ref.repair_county(county text, tract text) RETURNS text ...
-- returns county when present, else left(tract, 5) when the tract is 11 digits
```

The repair is not silent. The fact table carries a boolean:

```sql
(k.county_code = 'NA' AND k.census_tract <> 'NA') AS county_was_repaired
```

So any analysis can exclude derived geography with one predicate, and the 236 are countable forever.

### 2.2 Absence kept, with the reason recorded

This is the most important of the five and the easiest to get wrong. HMDA writes "no value" in at least five different ways in the same column, and they do not mean the same thing.

| the source says | what it means |
|---|---|
| `NA` | not applicable to this application |
| `Exempt` | the institution uses the partial reporting exemption |
| `9999` | there is no co-applicant |
| `8888` | not applicable |
| `1111` | exempt, written as a numeric sentinel |

Casting all of these to `NULL` throws away the distinction, and the distinction is the analysis. An interest rate that is `NA` because the application was denied is a different fact from an interest rate withheld by an exempt filer. So the model stores both the `NULL` and the reason for it.

```sql
ref.to_num(k.rate_spread)      -- the value, or NULL
ref.na_reason(k.rate_spread)   -- why it is NULL
```

Measured across the fact table:

| column | value present | not applicable | exempt filer |
|---|---|---|---|
| `income` | 1,543,883 | 210,938 | 19 |
| `loan_to_value_ratio` | 1,238,194 | 468,594 | 48,058 |
| `rate_spread` | 840,172 | 866,365 | 48,309 |

The exempt counts landing within 300 of each other on unrelated columns is the tell that this is a coherent cohort of institutions rather than scattered data entry loss. 48,131 applications are flagged `is_exempt_filer`.

**An honest oddity found while writing this doc.** For `debt_to_income_ratio` the reason function labels 647,063 rows `unparseable`. That is not a defect in the data, it is a defect in applying a numeric reason code to a column that is not always numeric. HMDA publishes DTI as a plain number for some applications and as a coarsened band for others, to limit re-identification:

```sql
SELECT CASE WHEN debt_to_income_band ~ '^-?[0-9.]+$' THEN 'plain number'
            WHEN debt_to_income_band IS NULL THEN 'null'
            ELSE 'band string' END, count(*)
FROM marts.fct_application GROUP BY 1;
-- band string  647,063   (e.g. '20%-<30%', '>60%')
-- null         565,552
-- plain number 542,231   (36 to 49 only)
```

The plain numbers only ever run 36 to 49, because that is the range the Bureau publishes precisely. Everything outside it is banded. The model therefore keeps DTI as `debt_to_income_band text` rather than numeric, which is correct, and the `unparseable` label on the band rows is cosmetic noise that a later revision should rename. It is recorded here rather than quietly tidied away, because "the reason column is slightly wrong on one of four columns" is the kind of thing a reviewer is entitled to find in the documentation rather than in the data.

### 2.3 Quarantined: 573 impossible values

Three domain rules, declared once, applied to every row.

| rule | what it catches | 2022 | 2023 | 2024 | 2025 |
|---|---|---|---|---|---|
| `interest_rate_not_a_percentage` | rate above 50, one row reports 450.0 | 1 | 0 | 0 | 0 |
| `ltv_not_a_ratio` | ratio above 300, largest 86,496,900 | 138 | 162 | 167 | 105 |
| `loan_amount_not_positive` | amount at or below zero | 0 | 0 | 0 | 0 |

A rate of 450.0 is almost certainly 4.50 typed without the decimal point. An LTV of 86,496,900 is a property value in an LTV column. Neither can be true, and neither can be corrected with any confidence, so neither is guessed at.

They are also not deleted. They move to `marts.quarantine_application`, which is the fact table's structure plus two columns:

```sql
CREATE TABLE marts.quarantine_application (
  LIKE marts.fct_application,
  violated_rule text NOT NULL,
  detected_at   timestamptz NOT NULL DEFAULT now()
);
```

So `SELECT violated_rule, count(*) FROM marts.quarantine_application GROUP BY 1` is a permanent, queryable statement of what this model refused and why. The alternative designs are worse in specific ways. Deleting them destroys the evidence. Leaving them in poisons every average. Clamping them to a plausible value invents data. Quarantine keeps all three options open to whoever comes next.

The step is idempotent. The insert carries a `NOT EXISTS` guard, so re-running `006` on a built database finds nothing new rather than duplicating the quarantine.

Order matters here. The bridge rows for a quarantined application are deleted first, then the fact row, and only then are the `CHECK` constraints added. Adding the constraints first would abort the whole build on row one.

### 2.4 Kept and numbered: 2,776 duplicate rows

The Bureau strips every loan identifier before publication, so the register has no candidate key at all. 2,081 hash groups contain more than one byte-identical row, 2,776 rows in total are excess, and the largest single group has **77 identical rows**.

Whether that is 77 genuinely identical applications or one filer submitting 77 times cannot be determined from the data, and anyone who tells you otherwise is guessing. So the model does not choose. It numbers them.

| `dup_seq` | rows |
|---|---|
| 1 | 1,752,070 |
| 2 | 2,081 |
| 3 | 301 |
| 4 | 135 |
| 5 to 77 | 259 |

Deduplicating would have been the conventional move and would have been wrong. If 77 identical applications are real, deleting 76 of them understates that lender's volume. Keeping them with an occurrence number means both readings stay available, and the count is stated rather than hidden.

### 2.5 Reported, not fixed: 27,229 contradictions

27,229 applications carry a denial reason where the outcome was not a denial, and 21,665 of those are on **originated** loans, which cannot be both approved and refused.

This is a filer system defect, it is stable at 1.33 to 1.63 percent in every year, and this repository has no standing to correct a regulatory submission. It is measured, given a documented tolerance, and checked on every build. Phase 07 covers the mechanism.

---

## 3. The key, and why it is a hash

With no natural key and no identifier, a surrogate is unavoidable. An identity column would have been one line of SQL and would have produced **different keys on every rebuild**, which means nobody could reproduce a result of this project and compare row for row.

```sql
WITH keyed AS (
  SELECT l.*,
         md5(l::text) AS row_hash,
         row_number() OVER (PARTITION BY md5(l::text)
                            ORDER BY l.lei, l.census_tract) AS dup_seq
  FROM raw.raw_lar l
)
SELECT row_number() OVER (ORDER BY k.row_hash, k.dup_seq)::bigint AS application_sk, ...
```

`md5(l::text)` hashes the whole row as the database renders it, so the key is a function of the published content and nothing else. `dup_seq` disambiguates identical rows. `(row_hash, dup_seq)` is the business key and carries a unique constraint. `application_sk` is a compact `bigint` derived from the same deterministic ordering, kept because joining on a 32 character string four million times is slower than joining on an integer.

This was verified across two independent machines, a Linux container and a Windows 11 laptop running PostgreSQL 18, building from the same published files. Denial rates matched to one decimal place. That is the whole point of the design.

The cost is stated rather than hidden: the unique index on the hash is 25 MB per partition, roughly 114 MB across four years. Phase 09 considers hashing to a `bigint` instead.

---

## 4. Unpivoting the repeating columns, and the trap inside it

Race, ethnicity, denial reason and automated underwriting system arrive as numbered columns: `applicant_race_1` through `applicant_race_5`, and the same again for a co-applicant. That is a first normal form violation, and unpivoting it is not tidiness. It is the difference between a right and a wrong answer.

```sql
CREATE TABLE marts.br_application_race AS
SELECT k.activity_year, k.application_sk, v.party, v.slot, v.race_code
FROM marts.stg_repeating s
JOIN marts.stg_keys k ON k.row_hash = s.row_hash AND k.dup_seq = s.dup_seq
CROSS JOIN LATERAL (VALUES
  ('applicant',1,s.applicant_race_1), ('applicant',2,s.applicant_race_2), ...
  ('co_applicant',1,s.co_applicant_race_1), ...
) AS v(party, slot, race_code)
WHERE v.race_code IS NOT NULL AND btrim(v.race_code) <> '';
```

| bridge | rows |
|---|---|
| `br_application_race` | 3,662,829 |
| `br_application_ethnicity` | 3,597,440 |
| `br_underwriting_system` | 1,075,534 |
| `br_denial_reason` | 438,591 |

Two filters are applied while unpivoting, and both are deliberate. Denial reason code `10` and AUS code `6` both mean "not applicable", so storing them would create bridge rows asserting that a reason was given when none was. They are excluded at build time, which is why `br_denial_reason` has 438,591 rows rather than several million.

### 4.1 The hierarchy trap

HMDA race codes are hierarchical. `2` is Asian. `22` is Chinese. `21` is Asian Indian. An applicant reporting Chinese in slot 1 and Asian Indian in slot 2 has reported **two subcategories of one race**, not two races.

Counting distinct codes without collapsing subcategories to their parent gives this:

```sql
-- naive
SELECT count(*) FROM (
  SELECT activity_year, application_sk FROM marts.br_application_race
  WHERE party='applicant' GROUP BY 1,2 HAVING count(DISTINCT race_code) > 1) z;
-- 106,971

-- rolled up to the top level parent
SELECT count(*) FROM (
  SELECT activity_year, application_sk FROM marts.br_application_race
  WHERE party='applicant' AND race_code ~ '^[1-5]'
  GROUP BY 1,2 HAVING count(DISTINCT left(race_code,1)) > 1) z;
-- 18,051
```

**106,971 against 18,051.** The naive count overstates multi-race applicants by a factor of six. This is the single most dangerous thing in the dataset for anyone doing demographic analysis, and the only reason it was caught is that the number looked too large to be plausible and was checked against the code list.

It is also why the bridge stores the **code**, not a label, and not `derived_race`. `derived_race` collapses anyone reporting two or more races into a single "2 or more minority races" bucket, so relying on it makes every multi-race applicant vanish from every individual race group. The bridge keeps what was actually reported and leaves the rollup to the query, where it is visible.

---

## 5. Geography, and the 16,059 that have none

16,059 applications have no census tract and 13,345 have no county even after the repair in 2.1. Together that is 0.9 percent of the file.

```sql
coalesce(nullif(k.census_tract,'NA'),'UNKNOWN')
coalesce(ref.repair_county(k.county_code, k.census_tract),'UNKNOWN')
coalesce(nullif(k.derived_msa_md,'NA'),'UNKNOWN')
```

Each geography dimension carries an explicit `UNKNOWN` row for every year, so the foreign key holds and no row is dropped for want of an address. An analyst who wants to exclude them writes `WHERE census_tract <> 'UNKNOWN'`, which is a decision they have made and can be asked about. An inner join that silently drops them is a decision nobody made.

---

## 6. The build in one pass, and why it is not slower for it

The whole transform is four statements: build the dimensions, insert the fact, unpivot the bridges, apply the constraints. No row by row processing, no cursors, no procedural code, no Python.

The fact insert takes 6 minutes 18 seconds for 1.75 million rows. The bridges take 36 seconds for 8.7 million bridge rows, which is only possible because `md5(l::text)` is computed once into an `UNLOGGED` staging table and reused by all four, rather than recomputed four times over 1.75 million rows.

```sql
CREATE UNLOGGED TABLE marts.stg_repeating AS
SELECT md5(l::text) AS row_hash, ... FROM raw.raw_lar l;
```

`UNLOGGED` skips write-ahead logging, which is safe precisely because the table is disposable: it is dropped at the end of `004` and can be rebuilt from `raw` at any time. Both staging tables are dropped before the build finishes, so the shipped model contains no scratch.

---

## 7. What is worth defending in a review

| choice | the alternative | why this one |
|---|---|---|
| Quarantine table | delete the 573 bad rows | the evidence survives and the refusal is queryable |
| `md5(row)` plus occurrence | identity column | a rebuild on another machine produces identical keys |
| Keep and number duplicates | deduplicate to 1,752,070 | which reading is true is not determinable, so neither is assumed |
| Store the reason for a NULL | cast everything to NULL | "denied so no rate" and "exempt filer" are different facts |
| Repair county from tract | leave it missing | the first five tract digits are the county FIPS by construction |
| Bridge stores codes | bridge stores `derived_race` | `derived_race` erases multi-race applicants |
| Roll subcategories up in the query | count distinct codes | the naive count overstates multi-race by a factor of six |
| Report the 27,229, do not fix | correct or drop them | a regulatory submission is not this repository's to amend |
