# Phase 02: Profiling the raw data

What 1,755,419 rows actually contain, before anything was modelled. This phase exists to answer one question: **can this data be trusted to answer the question in phase 01?**

Previous phase: [01 Sourcing and provenance](01_sourcing_and_provenance.md) · Next phase: [03 Landing the raw layer](03_landing_the_raw_layer.md)

---

## 1. Why profile before modelling

A dataset can be structurally perfect and analytically worthless. The only way to tell them apart is to measure it, and the measurement has to happen before the model is designed, because the findings change the design.

This phase does four things in order: check the data is real, check it joins, measure what is missing, and find what contradicts itself.

An earlier candidate dataset for this project failed the first of those four tests and was abandoned after profiling. That is the point of the phase: it is cheaper to reject a dataset than to publish an analysis built on one.

---

## 2. Is it real?

Synthetic data announces itself. Two tests settle it quickly.

### 2.1 Benford's law on 1.75 million loan amounts

Naturally occurring financial amounts follow a predictable first-digit distribution. Generated ones usually do not.

| first digit | observed | Benford predicts |
|---|---|---|
| 1 | 27.70% | 30.10% |
| 2 | 18.22% | 17.61% |
| 3 | 12.58% | 12.49% |
| 4 | 10.40% | 9.69% |
| 5 | 11.52% | 7.92% |
| 6 | 7.08% | 6.69% |
| 7 | 5.77% | 5.80% |
| 8 | 3.80% | 5.12% |
| 9 | 2.93% | 4.58% |

A clear monotonic decline that tracks the curve. One honest deviation: digit 5 is over-represented at 11.52 percent against 7.92. That is not a sign of fabrication, it is the public file's own rounding. HMDA rounds published loan amounts to the nearest ten thousand dollars, which clusters values on round numbers and lifts 5. Noticing the deviation and knowing its cause is the useful part.

```sql
WITH v AS (
  SELECT substring(regexp_replace(loan_amount, '[^1-9]', '', 'g') from 1 for 1) AS fd
  FROM raw.raw_lar WHERE ref.to_num(loan_amount) > 0
)
SELECT fd::int AS first_digit, count(*),
       round(100.0*count(*)/sum(count(*)) OVER (), 2) AS observed_pct,
       round((log(10, 1 + 1.0/fd::int)*100)::numeric, 2) AS benford_pct
FROM v WHERE fd <> '' GROUP BY 1 ORDER BY 1;
```

### 2.2 Distribution shape

Real money is skewed. Loan amount has a median of 295,000 against a mean of 641,524 and a maximum of 283,505,000. Property value has a median of 635,000 against a mean of 1,241,718. A useful quick test is to compare the observed standard deviation with the standard deviation a uniform distribution over the same range would have, which is the range divided by the square root of twelve. For these columns the ratio is about 0.04, meaning the data is nothing like uniform. For a generated dataset that ratio sits at 1.00.

**Verdict: real.**

---

## 3. Does it join?

Five sources have to line up before anything can be modelled. Every check returned zero problems, in every year.

| year | lenders in the register | missing from that year's transmittal sheet | missing from the lender file | MSAs missing from the MSA file | census tracts |
|---|---|---|---|---|---|
| 2022 | 802 | 0 | 0 | 0 | 5,227 |
| 2023 | 773 | 0 | 0 | 0 | 5,206 |
| 2024 | 757 | 0 | 0 | 0 | 5,184 |
| 2025 | 756 | 0 | 0 | 0 | 5,203 |

**And there is no schema drift.** All four registers have identical 99 columns and all four transmittal sheets identical 10. That is unusual for multi-year regulatory files and worth verifying rather than assuming.

```sql
-- zero rows means every lender in the register has a name
SELECT DISTINCT lei, activity_year FROM raw.raw_lar
EXCEPT
SELECT lei, activity_year FROM raw.raw_ts;
```

---

## 4. What is missing, and why it is missing

This is the single most important section for anyone using this data, because the missingness is structural rather than random and treating it as random produces wrong answers.

### 4.1 Usable values by column, across all 1,755,419 rows

| column | `NA` | `Exempt` | usable | usable % |
|---|---|---|---|---|
| income | 210,984 | 0 | 1,544,435 | 88.0% |
| property_value | 290,839 | 48,061 | 1,416,519 | 80.7% |
| loan_to_value_ratio | 468,594 | 48,058 | 1,238,767 | 70.6% |
| interest_rate | 585,907 | 48,060 | 1,121,452 | 63.9% |
| debt_to_income_ratio | 517,639 | 48,005 | 1,000,893 | 57.0% |
| rate_spread | 866,930 | 48,309 | 840,180 | 47.9% |
| total_loan_costs | 952,358 | 48,063 | 754,996 | 43.0% |

Two patterns to read here.

**The `NA` counts vary hugely and are explained by the outcome.** An interest rate does not exist for an application that was denied or withdrawn, and a rate spread only exists for loans priced above a threshold. So `interest_rate` being 36 percent absent is not a quality problem, it is the shape of the process. Any analysis of pricing has to restrict itself to originated loans, and this table is why.

**The `Exempt` counts sit at almost exactly 48,060 on every column.** That is not coincidence. HMDA grants a partial reporting exemption at institution level, so exempt filers withhold the same set of fields on every application. Those 48,000 rows are a coherent cohort, not scattered nulls, and treating them as a cohort is more honest than treating them as noise.

### 4.2 Sentinel codes, which are not missing data

| code | rows | share | what it means |
|---|---|---|---|
| `co_applicant_age = 9999` | 989,860 | 56.4% | there is no co-applicant |
| `derived_race = Race Not Available` | 429,313 | 24.5% | not reported |
| `derived_ethnicity = Not Available` | 406,829 | 23.2% | not reported |
| `derived_sex = Sex Not Available` | 289,120 | 16.5% | not reported |
| `applicant_age = 8888` | 194,303 | 11.1% | not applicable |
| `census_tract = NA` | 16,059 | 0.9% | no tract recorded |
| `county_code = NA` | 13,580 | 0.8% | no county recorded |

The first row is the important one. 989,860 applications have `co_applicant_age = 9999`, and that means **there is no second applicant**, which is a fact, not an absence. Converting it to NULL and then filtering on "not null" silently throws away every single-applicant application, which is more than half the data.

This is why the model preserves the *reason* for a NULL rather than only the NULL. Phase 04 covers the mechanism.

### 4.3 The demographic reporting gap, which is a finding in its own right

Nearly a quarter of applications have no recorded race. For a project about disparity in lending outcomes that is not a footnote: any measured gap is measured on the three quarters of applicants who did report. The direction of the bias is unknown, and saying so is more useful than pretending the 24.5 percent does not exist.

---

## 5. What contradicts itself

Five integrity problems, measured across all four years.

| finding | rows | verdict |
|---|---|---|
| Denial reason present where the action taken is not a denial | 27,229 | **source defect**, filer error |
| Loan-to-value ratio above 300, largest 86,496,900 | 572 | **impossible**, quarantined |
| Interest rate of 450.0 | 1 | **impossible**, quarantined |
| Byte-identical duplicate rows | 2,081 groups, 2,776 excess rows | **unresolvable**, kept and numbered |
| County missing while census tract present | 236 | **recoverable**, repaired |

### 5.1 The denial reason contradiction is concentrated, not random

27,229 applications carry a denial reason where the outcome was not a denial, which is 1.55 percent of the file and sits between 1.33 and 1.63 percent in **every single year**. That stability says systematic, not accidental.

The breakdown is what makes it a finding: **21,665 of them are on originated loans**, which cannot be both approved and refused. It is concentrated in 167 institutions across 373 lender-years, led by Advantage Federal Credit Union with 2,358, RCN Capital with 1,949 and ServU Federal Credit Union with 1,909. Those look like loan origination systems populating the field regardless of outcome.

This project cannot fix it and does not try. It is quantified and reported. See phase 07.

### 5.2 There is no primary key

The Bureau strips every loan identifier before publication, so the register has no candidate key at all, and 2,081 groups of byte-identical rows exist. Whether each group is two genuinely identical applications or one filer submitting twice cannot be determined from the data. Phase 04 explains what the model does about it.

### 5.3 The published code list does not cover the published data

Building a code-to-label reference table and then anti-joining it against the data found values the regulator documents nowhere:

| code field | value | rows |
|---|---|---|
| `applicant_credit_score_type` | 12 | 27,716 |
| `applicant_credit_score_type` | 11 | 26,143 |
| `applicant_credit_score_type` | 15 | 23,669 |
| `applicant_credit_score_type` | 14 | 1,838 |
| `applicant_credit_score_type` | 13 | 801 |
| `denial_reason_1` | 1111 (Exempt) | 31,821 |

**80,167 rows carry a credit score type code that the CFPB's public code list does not define.** These are newer scoring models added to the filing instructions after the public documentation page was written. The anti-join that found them is now a permanent build assertion, so the next undocumented code is caught automatically rather than discovered by accident.

```sql
-- the pattern: any code in the data with no label is a build failure
SELECT f.action_taken, count(*)
FROM marts.fct_application f
WHERE NOT EXISTS (
  SELECT 1 FROM ref.ref_code r
  WHERE r.code_field = 'action_taken' AND r.code_value = f.action_taken)
GROUP BY 1;
```

---

## 6. Fitness verdict

| requirement from phase 01 | met? | evidence |
|---|---|---|
| Real data, not generated | yes | Benford tracks the curve; distributions are log-normal |
| Sources join cleanly | yes | zero orphans on every relationship, in every year |
| An outcome to analyse | yes | 8 action-taken codes, 17 to 18 percent denied |
| Applicant demographics | yes, with a caveat | present, but 24.5 percent unreported |
| Geography fine enough to hold constant | yes | 5,200 tracts, each with census attributes |
| More than one lender | yes | 756 to 802 per year, 286 holding companies |
| Enough volume for tuning to matter | yes | 1,755,419 rows |
| Repayment performance | **no** | HMDA records decisions, not outcomes |
| A credit score to control for | **no** | not collected by the regulator |

**Conclusion: fit for a study of access to credit and disparity in lending decisions. Not fit for a study of credit risk performance.** The two missing items are not defects in the data, they are the boundary of what HMDA is, and every finding in this project has to be stated inside that boundary.

The absence of a credit score is the single most important limitation and is repeated wherever a disparity is reported. It means no finding here is causal.
