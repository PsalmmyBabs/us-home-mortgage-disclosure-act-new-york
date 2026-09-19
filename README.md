# Mortgage lending in New York, 2022 to 2025

A PostgreSQL analytics project on 1,755,419 real mortgage applications, built from published regulatory data, documented as ten phases, and **runnable in your browser without installing anything**.

### ▶ [Open SQL Playground](https://PsalmmyBabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/) · [Browse the Data Dictionary](https://PsalmmyBabs.github.io/us-home-mortgage-disclosure-act-new-york/catalog/) &middot; [Project Home](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/)

The playground gives you fifteen tables, a SQL box and the ten queries below, running in your browser. Nothing is installed, no account is created, and no data leaves your machine. The data dictionary documents every table, column, key and index, generated from the live catalogue rather than written by hand.

---

## The question

> Who gets access to mortgage credit in New York, on what terms, and does the answer differ by applicant group once income, product, neighbourhood and lender are held constant?

## What the data says

**The finding with the clearest action is not the one you would expect.** In the 532 census tracts where at least four lenders each made 30 or more decisions, the median gap between the most and least restrictive lender **in the same tract** is 30.6 points. Which lender an applicant approaches matters more than anything else measured here.

| finding | figure |
|---|---|
| Denial rate spread between lenders in the same census tract | **30.6 points** median, 97.3 at the extreme |
| Applications ending in "file closed for incompleteness" | 0.2% to 28.5% between lenders, **a factor of 142** |
| Black denial rate against White, 2025 | 39.6% against 22.4% |
| The same gap for applicants earning over 200k | 30.2% against 15.7% |
| Home improvement loans, Black applicants | 64.5% denied, on 209,703 decided applications |
| Census tracts with 100+ decided applications from both groups | 62, and the Black rate is higher in **60** |
| Share of the 2023 market tightening that was products denying more, not the product mix changing | **76%** |
| Rate spread paid by approved Black borrowers, against White | 1.8 times, on both mean and median |

**None of this is causal.** HMDA does not contain a credit score, so the honest claim is narrower and still substantial: the disparity is not explained by income, product, neighbourhood or lender choice, because it persists after holding each of those constant. Whether it is explained by creditworthiness cannot be tested with this data. [Phase 08 section 12](docs/08_analysis.md#12-what-this-analysis-cannot-say) states the limits in full.

## What is in the model

1,755,419 applications from four sources, in a 15 table star schema:

```
fct_application          partitioned by year, 1,754,846 rows
  dim_institution        year-keyed, 756 to 802 lenders per year
  dim_tract              year-keyed, ~5,200 census tracts
  dim_county, dim_msa, dim_date
  dim_loan_product       junk dimension, 194 real combinations of 7 codes
  dim_dwelling           junk dimension, 41 combinations
  dim_applicant_profile
  br_application_race    bridge, 3,662,829 rows
  br_application_ethnicity, br_denial_reason, br_underwriting_system
quarantine_application   573 rows that could not be true
ref_code                 450 code-to-label mappings across 54 columns
```

[Phase 04](docs/04_data_model.md) maps all 99 source columns to their destination and gives the evidence behind every split.

## The ten phases

| | what it covers | the part worth reading |
|---|---|---|
| [01](docs/01_sourcing_and_provenance.md) | Sourcing and provenance | Publication vintages, and why mixing them changes the numbers |
| [02](docs/02_profiling_the_raw_data.md) | Profiling the raw data | Benford's law, and 80,167 rows carrying a code the regulator documents nowhere |
| [03](docs/03_landing_the_raw_layer.md) | Landing the raw layer | Why the raw layer is all `text` and is never edited |
| [04](docs/04_data_model.md) | Designing the data model | The four splitting rules, with measurements behind each one |
| [05](docs/05_building_the_objects.md) | Building the objects | Partitioning, constraints after the load, and the honest cost of a reproducible key |
| [06](docs/06_transforming_raw_into_the_model.md) | Transforming raw into the model | The five things that happen to a bad record, and a trap that overstates multi-race applicants sixfold |
| [07](docs/07_quality_assertions.md) | Quality assertions | Build errors against source defects, and a gap found while writing the document |
| [08](docs/08_analysis.md) | The analysis | Nine findings, including one where my prediction was backwards |
| [09](docs/09_performance_tuning.md) | Performance tuning | An index the planner ignored, and 125 MB of indexes that should never have existed |
| [10](docs/10_playground.md) | The browser playground | A silent dialect difference that changed a published figure by 20 percent |

Each phase ends with a table headed *what is worth defending in a review*.

## Three things this repository does differently

**It shows the mistakes.** Phase 08 keeps a prediction of mine that the measurement contradicted. Phase 09 shows an index I built being ignored by the query planner, and 125 MB of indexes that duplicated a primary key. Phase 07 documents an assertion gap found while writing the document rather than patching it quietly. A build that never admits to a gap is not a build anyone should trust.

**Nothing is deleted.** All 1,755,419 published rows are accounted for in a query, not a claim:

```sql
SELECT (SELECT count(*) FROM raw.raw_lar)                  AS published,
       (SELECT count(*) FROM marts.fct_application)        AS modelled,
       (SELECT count(*) FROM marts.quarantine_application) AS quarantined;
-- 1,755,419 = 1,754,846 + 573
```

Impossible values are quarantined with the rule they broke rather than dropped. Missing values keep the *reason* they are missing, because "denied so there is no interest rate" and "withheld by an exempt filer" are different facts. Byte-identical duplicates are numbered rather than deduplicated, because which reading is true is not determinable from the data.

**The keys are reproducible.** HMDA has no primary key: the Bureau strips every loan identifier before publication. An identity column would produce different keys on every rebuild, so the key is `md5` of the source row plus an occurrence number. Verified by building the whole model on two independent machines, a Linux container and a Windows laptop, and getting denial rates that match to one decimal place.

## Documentation that cannot go stale

`migrations/009_comments.sql` puts the description of every table and all 175 table columns into the PostgreSQL catalogue itself, and `catalog/build_catalog.py` generates the published dictionary from `pg_catalog` at build time.

So the dictionary cannot describe a column that no longer exists, the descriptions are versioned with the DDL and reviewed in the same diff, and anyone connected to the database sees them without opening a browser:

```sql
\d+ marts.fct_application
```

The build reports coverage and names any column with no comment, which makes an undocumented column a number rather than an oversight. It currently reports 100 percent.

## Verification

```sql
SELECT * FROM marts.assert_results ORDER BY severity, assertion;
```

Eight assertions, split into `build_error` (must be zero) and `source_defect` (a real problem in the filed data, with a documented tolerance, so the build is not permanently red over something outside its control). `marts.assert_failures` returns rows only when the build is genuinely broken, so one command can gate a merge:

```bash
test "$(psql -tAqc 'SELECT count(*) FROM marts.assert_failures' hmda)" = "0"
```

The playground has its own test: `playground/parity_test.py` runs all ten published queries against PostgreSQL and against the browser build, and fails on any difference.

## Repository layout

```
migrations/     000 to 009, run in order, about eight minutes end to end
seed/           the loader script and one small derived CSV
docs/           the ten phase documents
docs/playground/  the published site
docs/catalog/     the published data dictionary
playground/     the source that builds the site
catalog/        the source that builds the dictionary
RUNBOOK.md      exact source files, vintages and download links
SETUP_WINDOWS.md  building the database from nothing on Windows
```

## Rebuild it yourself

Everything here is reproducible from public files. [`RUNBOOK.md`](RUNBOOK.md) names the exact datasets and vintages, [`SETUP_WINDOWS.md`](SETUP_WINDOWS.md) is the step by step build, and [`docs/DEPLOY_PLAYGROUND.md`](docs/DEPLOY_PLAYGROUND.md) rebuilds and publishes the browser version.

The loan registers are 638 MB and are not committed. The lender file is, because it is small and derived, which means building the database needs nothing but PostgreSQL and the downloads named in the runbook.

## Sources and licence

Loan Application Register, Transmittal Sheet and MSA/MD descriptions: Consumer Financial Protection Bureau, via the [HMDA Data Browser](https://ffiec.cfpb.gov/data-browser/). United States federal government works, no copyright under 17 U.S.C. 105.

Institution hierarchy, asset size, CRA rating and minority-owned flag: Federal Reserve Bank of Philadelphia, HMDA Lender File (Avery File).

The published register is modified by the Bureau to protect applicant privacy. This project makes no attempt at re-identification and does not combine these files with any other source for that purpose.

---

Built by [Samuel Babajide](https://github.com/PsalmmyBabs). Questions and corrections are welcome in the issues.
