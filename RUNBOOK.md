# Runbook: building the database from nothing

Run these in order. Every step is idempotent, so a failed run can be restarted from the top.

## Prerequisites

- PostgreSQL 14 or later (built and tested on 16)
- Python 3 with `pandas` and `openpyxl`, for the lender spreadsheet only
- About 3 GB of disk for the full four-year build

## Step 0: get the data

The files are not in this repository, because the loan register alone is 160 MB per year. Download them yourself.

**Loan application registers**, one per year, from the HMDA Data Browser at `ffiec.cfpb.gov/data-browser`. Filter to **state = New York**, select the year, and apply **no lender filter**. Export CSV.

**Transmittal sheet and MSA descriptions**, one pair per year, from the publication page matching that year's vintage:

| year | vintage | transmittal sheet | MSA descriptions |
|---|---|---|---|
| 2022 | three-year | `files.ffiec.cfpb.gov/static-data/three-year/2022/2022_public_ts_three_year_csv.zip` | `..._msamd_three_year_csv.zip` |
| 2023 | one-year | `files.ffiec.cfpb.gov/static-data/one-year/2023/2023_public_ts_one_year_csv.zip` | `..._msamd_one_year_csv.zip` |
| 2024 | one-year | `files.ffiec.cfpb.gov/static-data/one-year/2024/2024_public_ts_one_year_csv.zip` | `..._msamd_one_year_csv.zip` |
| 2025 | snapshot | `files.ffiec.cfpb.gov/static-data/snapshot/2025/2025_public_ts_csv.zip` | `2025_public_msamd_csv.zip` |

The vintages differ because the Data Browser serves the most complete dataset available for each year. That is recorded in `ref.ref_source_vintage` and must be quoted whenever the years are compared.

**Lender file**, one file covering 2018 to 2025, from the Philadelphia Fed:
`philadelphiafed.org/-/media/FRBP/Assets/Surveys-And-Data/hmda/hmda-2018-present.xlsx`

Arrange them like this:

```
data/
├── 2022/  state_NY.csv  transmittal_sheet.csv  msamd.csv
├── 2023/  state_NY.csv  transmittal_sheet.csv  msamd.csv
├── 2024/  state_NY.csv  transmittal_sheet.csv  msamd.csv
├── 2025/  state_NY.csv  transmittal_sheet.csv  msamd.csv
└── lender_file.xlsx
```

## Step 1: create the database

```bash
createdb hmda
```

## Step 2: load the raw layer

```bash
./seed/load_raw.sh ./data hmda
```

This creates `migrations/000_raw_layer.sql`'s tables and copies every file in. It prints row counts at the end. Compare them against the expected figures it shows; a mismatch means your Data Browser filters differ from the ones used here.

Takes about 2 minutes.

## Step 3: run the migrations, in order

```bash
for f in migrations/0*.sql; do
  echo "== $f"
  psql -d hmda -v ON_ERROR_STOP=1 -f "$f"
done
```

Or one at a time if you prefer to watch:

| file | what it does | time |
|---|---|---|
| `000_raw_layer.sql` | raw tables and the vintage table (already run by step 2) | instant |
| `001_schemas.sql` | `raw` / `ref` / `marts` schemas, and the three helper functions | instant |
| `002b_ref_code_seed.sql` | 450 code-to-label mappings | instant |
| `002_dimensions.sql` | the eight dimensions | 7 sec |
| `003_fact.sql` | the partitioned fact table | **6 min** |
| `004_bridges.sql` | the four bridge tables | 36 sec |
| `005_constraints_indexes.sql` | primary keys, foreign keys, indexes | 23 sec |
| `006_quarantine_and_checks.sql` | quarantine rows failing domain rules, then apply the rules | 6 sec |
| `007_views.sql` | the labelled views | instant |
| `008_assertions.sql` | the quality assertion framework | instant |

Total, about 8 minutes.

> `002b` runs before `002` deliberately. `ref_code` has no dependencies and the dimensions do not need it, but the naming keeps the reference seed next to the dimension step it belongs with. Alphabetical order in the loop puts `002` before `002b`, which also works, since neither depends on the other.

## Step 4: check the build

```sql
SELECT * FROM marts.assert_failures;     -- must return zero rows
SELECT * FROM marts.assert_results;      -- the full picture, including known source defects
```

`assert_failures` returning nothing means the build is sound. `assert_results` will show `denial_reason_on_non_denial` at about 1.55 percent, flagged as a known source defect within tolerance. That is filers submitting inconsistent data, not a problem with this pipeline.

## Step 5: query it

Codes are stored as codes. Use the views for English:

```sql
SELECT activity_year, applicant_race,
       round(100.0 * count(*) FILTER (WHERE is_denied)
                   / count(*) FILTER (WHERE is_decided), 1) AS denial_rate
FROM marts.v_application
WHERE is_decided
GROUP BY 1, 2
ORDER BY 1, 2;
```

## Rebuilding from scratch

Every migration drops and recreates what it owns, so re-running the whole sequence is safe. The fact table's surrogate keys are deterministic (an md5 of the source row plus an occurrence number), so a rebuild produces the same keys as the previous build. That matters: anyone who clones this repository and runs it gets the same `application_sk` values you did.
