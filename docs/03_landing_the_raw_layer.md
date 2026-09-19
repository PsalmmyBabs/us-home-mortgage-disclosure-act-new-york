# Phase 03: Landing the raw layer

Getting 1,755,419 rows into PostgreSQL exactly as published, with nothing cast, cleaned or interpreted. Built in pgAdmin apart from four bulk loads.

Previous phase: [02 Profiling the raw data](02_profiling_the_raw_data.md) · Next phase: [04 Designing the data model](04_data_model.md)

---

## 1. The principle: the raw layer has no opinions

Everything in `raw` is `text`. No numeric types, no dates, no constraints, no keys.

That looks lazy and is deliberate. The moment a loader casts `loan_amount` to numeric, it has made a decision about what `NA` and `Exempt` mean, and that decision is invisible to anyone reading the result. Landing everything as text moves every such decision downstream into `002_dimensions.sql` and `003_fact.sql`, where it is written in SQL, commented, and re-runnable.

Three rules follow:

1. **The raw layer mirrors the file.** Its shape is dictated by the publisher, not chosen.
2. **The raw layer is never edited.** No UPDATE, no DELETE, no cleaning. It keeps all 1,755,419 rows for the life of the project so anything can be re-derived.
3. **Interpretation happens once, downstream, in version control.**

The one exception is `raw.raw_msamd`, which gets `activity_year` set after each load, because the publisher's MSA file does not carry the year and the year is the only thing distinguishing one year's file from another's.

---

## 2. What gets built

| table | source | rows |
|---|---|---|
| `raw.raw_lar` | four loan application registers | 1,755,419 |
| `raw.raw_ts` | four transmittal sheets | 19,321 |
| `raw.raw_lender` | Philadelphia Fed lender file, filtered to 2022-2025 | 19,321 |
| `raw.raw_msamd` | four MSA description files | 1,662 |
| `ref.ref_source_vintage` | written by hand from the publication pages | 4 |

`ref.ref_source_vintage` is the only table in this phase containing anything not lifted from a file. It records which dataset vintage each year came from and when it was frozen, so provenance is queryable rather than living in a comment. Phase 01 section 4 explains why that matters.

---

## 3. Tooling: pgAdmin, except for four files

Everything in this project is plain SQL, and plain SQL runs in pgAdmin's Query Tool. The one exception is bulk loading.

| task | tool | why |
|---|---|---|
| Create schemas and tables | **pgAdmin Query Tool** | ordinary DDL |
| Load the four loan registers (139 to 200 MB each) | **psql `\copy`** | see below |
| Load the nine small files (10 KB to 8.7 MB) | **pgAdmin Import/Export** | comfortable at this size |
| Everything in phases 04 onward | **pgAdmin Query Tool** | ordinary SQL |

**Why `\copy` for the four big ones.** `COPY` is a server-side command: the PostgreSQL service reads the file itself, so it needs the file to be visible to the service account, which on Windows it usually is not. `\copy` is a psql client command: psql reads the file as you, streams it to the server over the existing connection, and needs no server-side file access. pgAdmin's Import/Export dialog does the same thing under the hood but is slow and fragile on a 200 MB file. So the honest answer to "why not do it all in the GUI" is that one tool streams a 200 MB file in a single pass and the other does not.

That is one command, run four times, with one filename changing each time.

---

## 4. Build it

### Step 1. Create the database

In pgAdmin, right-click **Databases**, choose **Create > Database**, name it `hmda`.

### Step 2. Create the raw layer

Open the Query Tool on `hmda`, open `migrations/000_raw_layer.sql`, read it, press F5.

It creates the `raw` and `ref` schemas, the four raw tables, and populates `ref_source_vintage`. Then open `migrations/000b_lender_table.sql` and do the same.

**Check:** the tables exist and are empty.

```sql
SELECT table_schema, table_name FROM information_schema.tables
WHERE table_schema IN ('raw','ref') ORDER BY 1,2;
```

### Step 3. Load the four loan registers

This is the one command-line step. In PowerShell:

```powershell
$env:Path += ";C:\Program Files\PostgreSQL\18\bin"
$env:PGCLIENTENCODING = "UTF8"
$env:PGPASSWORD = 'your-password'
```

Then once per year, changing only the filename:

```powershell
psql -U postgres -d hmda -q -c "\copy raw.raw_lar FROM 'C:/data/hmda_new_york_2022_three_years.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"
```

**Two things that will bite you if they are omitted.**

`ENCODING 'UTF8'` is not optional. psql on Windows takes its client encoding from the console codepage, usually WIN1252, and then fails on any UTF-8 byte it cannot map. The registers happen to be pure ASCII so they load either way, but the transmittal sheets and the lender file carry accented institution names and will fail without it.

A `\copy` command must be one unbroken line. Do not let an editor wrap it.

### Step 4. Load the nine small files in pgAdmin

For each of the four transmittal sheets: right-click `raw.raw_ts` > **Import/Export Data**, set Import, choose the file, tick Header, set Encoding to UTF8, Format csv, and run.

For each of the four MSA files: same, on `raw.raw_msamd`, but on the **Columns** tab deselect `activity_year`, because the publisher's file does not contain it. Then set it:

```sql
UPDATE raw.raw_msamd SET activity_year = 2022 WHERE activity_year IS NULL;
```

Run that immediately after each MSA import, changing the year, before importing the next one. Doing all four imports and then trying to set the year is not recoverable, because nothing in the file distinguishes them.

For the lender file: `seed/lender_file_2022_2025.csv` into `raw.raw_lender`, same settings.

### Step 5. Verify before going further

```sql
SELECT 'lar' AS t, activity_year AS yr, count(*) FROM raw.raw_lar GROUP BY 1,2
UNION ALL SELECT 'ts', activity_year, count(*) FROM raw.raw_ts GROUP BY 1,2
UNION ALL SELECT 'msamd', activity_year::text, count(*) FROM raw.raw_msamd GROUP BY 1,2
UNION ALL SELECT 'lender', year, count(*) FROM raw.raw_lender GROUP BY 1,2
ORDER BY 1,2;
```

Sixteen rows, and every one must match:

| | 2022 | 2023 | 2024 | 2025 |
|---|---|---|---|---|
| lar | 549,677 | 391,574 | 383,614 | 430,554 |
| ts | 4,484 | 5,129 | 4,926 | 4,782 |
| msamd | 413 | 413 | 418 | 418 |
| lender | 4,484 | 5,129 | 4,926 | 4,782 |

**A doubled count means a file was loaded twice.** That is the most common mistake here, and it is worth catching now rather than in phase 05, where a primary key on `dim_institution` will fail on the duplicates. The fix is to truncate that one table and reload it once.

```sql
TRUNCATE raw.raw_ts;   -- then reload all four transmittal sheets
```

Note that `lender` and `ts` agreeing exactly is itself a check: the Philadelphia Fed and the CFPB independently report the same number of filing institutions in each year.

---

## 5. Scripted alternative

`seed/load_raw.ps1` does all of step 3 and 4 in one command. It checks every file exists before touching the database, so a missing or misnamed file is reported in seconds rather than halfway through a 638 MB load, and it prints the verification table at the end.

```powershell
.\seed\load_raw.ps1
```

The script is for rebuilding. The manual route in section 4 is what you should do the first time, because watching each file land and each count come back is how you learn where the data actually is.

---

## 6. What the raw layer is worth

It looks like the least interesting phase and it is the one that makes everything else possible.

Because `raw.raw_lar` is untouched and complete, every downstream decision is reversible. When phase 06 quarantines 573 rows, they are still in raw. When phase 04 casts `Exempt` to NULL, the literal string is still in raw. When a question comes up in six months that nobody thought to ask, the answer is one query away rather than one re-download away.

And it is what makes the reconciliation assertion possible, which is the single check that proves the model did not lose anything:

```sql
SELECT (SELECT count(*) FROM raw.raw_lar)                    AS raw_rows,
       (SELECT count(*) FROM marts.fct_application)          AS modelled,
       (SELECT count(*) FROM marts.quarantine_application)   AS quarantined;
-- 1,755,419 = 1,754,846 + 573
```
