# Phase 07: Quality assertions

Eight checks that run on every build, a severity model that keeps a red light meaningful, and one honest gap found by writing this document.

Previous phase: [06 Transforming raw into the model](06_transforming_raw_into_the_model.md) · Next phase: [08 The analysis](08_analysis.md)

---

## 1. Why constraints are not enough

Phase 05 declared 25 check constraints, 62 foreign keys and 17 primary keys. Those state what cannot be **stored**. They cannot state what has to be true **across** tables:

- the fact plus the quarantine must add back up to the published row count
- every code in the fact must resolve to a published label
- `dim_tract` must hold exactly one row per tract per year
- every year in `dim_date` must actually appear in the fact

None of those is expressible as a column constraint, and all four are things that break silently when a build is changed. So they are written as assertions: a view that measures each condition and reports a status. The build is not finished when the DDL succeeds. It is finished when the assertions pass.

---

## 2. The severity model, which is the part worth arguing about

The obvious design is a list of checks that either pass or fail. It does not survive contact with real regulatory data, for one reason: **some of the problems in this dataset are real, permanent, and not mine to fix.**

27,229 applications carry a denial reason on a non-denial. That is a filer submission defect. It will be there next year and the year after. If it is a hard failure, the build is red forever, and a build that is always red is a build nobody looks at. If it is not checked at all, then the day it jumps from 1.5 percent to 15 percent nobody notices.

So every assertion is classified, and the classification is stored rather than implied:

```sql
CREATE TABLE ref.assertion_catalog (
  assertion   text PRIMARY KEY,
  severity    text NOT NULL CHECK (severity IN ('build_error','source_defect')),
  tolerance   numeric,             -- max acceptable share of rows, source defects only
  description text NOT NULL
);
```

| severity | meaning | tolerance | on breach |
|---|---|---|---|
| `build_error` | my pipeline is wrong | none, must be zero | **fail the build** |
| `source_defect` | the regulator's filers submitted something inconsistent | a documented share | fail only if it **worsens** past the tolerance |

A `source_defect` with a tolerance is a quantified, dated statement of a known problem. It says: this is wrong, this is how wrong, this is how much worse it is allowed to get before someone has to look. That is a different and more useful thing than either ignoring it or crying wolf about it.

---

## 3. The eight assertions and their live results

```sql
SELECT * FROM marts.assert_results ORDER BY severity, assertion;
```

| assertion | severity | failing rows | % of fact | tolerance | status |
|---|---|---|---|---|---|
| `fact_does_not_reconcile_to_raw` | build_error | 0 | 0.000 | | pass |
| `orphan_tract` | build_error | 0 | 0.000 | | pass |
| `row_hash_dup_seq_not_unique` | build_error | 0 | 0.000 | | pass |
| `tract_attributes_vary_within_year` | build_error | 0 | 0.000 | | pass |
| `unmapped_code` | build_error | 0 | 0.000 | | pass |
| `year_missing_from_fact` | build_error | 0 | 0.000 | | pass |
| `denial_reason_on_non_denial` | source_defect | 27,229 | 1.552 | 2.0% | known_issue_within_tolerance |
| `denied_without_reason` | source_defect | 0 | 0.000 | 1.0% | pass |

Each one exists because it protects a specific decision made earlier in the build.

| assertion | what it protects |
|---|---|
| `fact_does_not_reconcile_to_raw` | the phase 06 promise that nothing is deleted |
| `row_hash_dup_seq_not_unique` | the deterministic key, and therefore reproducibility |
| `unmapped_code` | the phase 05 decision to store codes and label them in views |
| `orphan_tract` | the `UNKNOWN` member design, and the year-grained geography |
| `tract_attributes_vary_within_year` | the phase 04 grain decision for `dim_tract` |
| `year_missing_from_fact` | a partition silently left empty after a reload |
| `denial_reason_on_non_denial` | the honesty of every denial-reason analysis |
| `denied_without_reason` | that a denial always carries a reason, which it does |

`denied_without_reason` returning zero is worth pausing on. Every one of the denied applications in 1.75 million rows carries at least one reason code. The field the filers get wrong is the one they populate when they should not, never the one they leave blank. That asymmetry is itself evidence for the "origination system fills the field regardless of outcome" explanation.

---

## 4. The source defect, quantified

27,229 applications carry a denial reason where the action taken is neither a denial nor a preapproval denial.

| year | contradictions | % of that year | of which on **originated** loans |
|---|---|---|---|
| 2022 | 8,897 | 1.62% | 7,147 |
| 2023 | 5,209 | 1.33% | 3,990 |
| 2024 | 6,103 | 1.59% | 4,784 |
| 2025 | 7,020 | 1.63% | 5,744 |
| **total** | **27,229** | **1.55%** | **21,665** |

Stability across four independent filing years in a range of 0.3 percentage points is what makes this systematic rather than accidental. It is concentrated in 167 institutions across 373 lender-years:

| institution | contradictions |
|---|---|
| RCN Capital, LLC | 2,385 |
| Advantage Federal Credit Union | 2,358 |
| ServU Federal Credit Union | 1,909 |
| Sidney Federal Credit Union | 1,040 |
| First Central Savings Bank | 1,015 |

The 2 percent tolerance is not a number chosen to make the check pass. The observed range is 1.33 to 1.63 percent, so 2 percent allows the defect to grow by about a quarter before it demands attention, and would catch any structural change in filer behaviour.

**What this means for the analysis.** Any count of denial reasons has to be restricted to actual denials:

```sql
SELECT r.label, count(*)
FROM marts.v_denial_reason r
WHERE r.is_denied            -- not optional
GROUP BY 1 ORDER BY 2 DESC;
```

Without that predicate, the top denial reasons in this dataset are contaminated by 21,665 loans that were approved and funded.

---

## 5. A gap found by writing this document

The `unmapped_code` assertion passes. It also only checks **one** column:

```sql
SELECT 'unmapped_code',
       (SELECT count(*) FROM marts.fct_application f
        WHERE NOT EXISTS (SELECT 1 FROM ref.ref_code r
                          WHERE r.code_field='action_taken'
                            AND r.code_value=f.action_taken))
```

Phase 02 found 80,000 rows carrying a credit score type code that the CFPB's public code list does not define. That finding is in the profiling document and **is not caught by the assertion that exists to catch exactly that class of problem**. The assertion was written against the column that mattered most and never generalised.

Generalising it is not hard, and the generalised version was run before writing this paragraph:

```sql
WITH coded(code_field, code_value) AS (
  SELECT 'action_taken',                action_taken                FROM marts.fct_application
  UNION ALL SELECT 'purchaser_type',    purchaser_type              FROM marts.fct_application
  UNION ALL SELECT 'preapproval',       preapproval                 FROM marts.fct_application
  UNION ALL SELECT 'hoepa_status',      hoepa_status                FROM marts.fct_application
  UNION ALL SELECT 'applicant_credit_score_type', applicant_credit_score_type FROM marts.fct_application
  UNION ALL SELECT 'submission_of_application',   submission_of_application   FROM marts.fct_application
)
SELECT c.code_field, c.code_value, count(*) AS rows
FROM coded c
WHERE c.code_value IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM ref.ref_code r
                  WHERE r.code_field = c.code_field AND r.code_value = c.code_value)
GROUP BY 1,2 ORDER BY 3 DESC;
```

| code field | value | rows |
|---|---|---|
| `applicant_credit_score_type` | 12 | 27,690 |
| `applicant_credit_score_type` | 11 | 26,121 |
| `applicant_credit_score_type` | 15 | 23,651 |
| `applicant_credit_score_type` | 14 | 1,838 |
| `applicant_credit_score_type` | 13 | 801 |

80,101 rows across five undefined values, and **nothing else**. The other five code fields are completely mapped, which is a useful result in its own right: it means `ref.ref_code` is right about everything except one column.

Those five values are newer credit scoring models added to the filing instructions after the CFPB's public code list page was written, so this is documentation lag rather than bad data. The right treatment is therefore a **`source_defect` with a tolerance**, not a `build_error`, and the five values get labelled as "scoring model not in the published code list".

This is left in the document rather than quietly patched into the code, because a reviewer who reads phase 02 and then phase 07 will notice the inconsistency, and the useful answer is "yes, here it is, here is the measurement, here is the fix" rather than a repository that never admits to a gap.

---

## 6. The CI gate

`marts.assert_failures` is the whole gate. It returns rows only when the build is genuinely broken, which means a `build_error` above zero or a `source_defect` past its tolerance.

```sql
CREATE VIEW marts.assert_failures AS
SELECT * FROM marts.assert_results WHERE status = 'FAIL';
```

One command decides whether a build ships:

```bash
test "$(psql -tAqc 'SELECT count(*) FROM marts.assert_failures' hmda)" = "0" \
  || { psql -c 'SELECT assertion, failing_rows, tolerance FROM marts.assert_failures' hmda; exit 1; }
```

Two properties make that usable. It exits non-zero only on real breakage, so it can gate a merge without being routinely overridden. And when it does fail it prints which assertion, how many rows and what the tolerance was, which is enough to act on without opening a database.

---

## 7. What is worth defending in a review

| choice | the alternative | why this one |
|---|---|---|
| Assertions as a view over the built model | checks inside the loading code | they can be re-run any time, by anyone, without rebuilding |
| Two severities | one pass/fail list | a permanent source defect would make the build permanently red |
| Tolerances stored in a table | thresholds hardcoded in a script | the threshold is queryable and reviewable alongside its rationale |
| Tolerance set at 2% against an observed 1.55% | set at 1.6%, or at 100% | leaves room for normal variation, catches a structural change |
| Reconciliation as an assertion | trust the build | it is the single check that proves nothing was silently dropped |
| Documenting the `unmapped_code` gap | fixing it quietly | a reviewer will find it, and finding it already measured is the better outcome |
