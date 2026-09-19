# Step-by-step setup on Windows

Written for your actual machine and your actual files. **Nothing gets copied, moved or renamed.** Your CSVs stay in `Downloads\hmda_new_york_2022-2025` and the loader reads them where they are.

Every command below goes into **PowerShell**, not Command Prompt and not pgAdmin. Each step says what you should see, so you can check before moving on.

About 12 minutes in total, of which 8 is the database building itself.

---

## What you already have

In `C:\Users\USER\Downloads\hmda_new_york_2022-2025`:

| year | loan register | transmittal sheet | MSA file |
|---|---|---|---|
| 2022 | `hmda_new_york_2022_three_years.csv` | `2022_transmittal_sheet.csv` | `2022_msamd.csv` |
| 2023 | `hmda_new_york_2023_one_year.csv` | `2023_transmittal_sheet.csv` | `2023_msamd.csv` |
| 2024 | `hmda_new_york_2024_one_year.csv` | `2024_transmittal_sheet.csv` | `2024_msamd.csv` |
| 2025 | `state_NY.csv` | `hmda_institution_names.csv` | `hmda_msamd.csv` |

Plus `hmda_lender_file.xlsx`, and the SQL files in the `Claude outputs` subfolder.

That is everything. The `data` subfolder and the `.7z` archives are leftovers and are not used.

---

## Step 1. Open PowerShell and check your tools

Press the Windows key, type `powershell`, press Enter. Then paste:

```powershell
$env:Path += ";C:\Program Files\PostgreSQL\18\bin"
psql --version
python --version
```

**You should see** `psql (PostgreSQL) 18.x` and a Python version.

If `psql` is not found, check which version folder you actually have:

```powershell
Get-ChildItem "C:\Program Files\PostgreSQL" -Directory
```

and put that number in the first line instead of 18.

> That `$env:Path` line lasts only as long as this PowerShell window. If you close it, run it again.

---

## Step 2. Install the two Python packages

```powershell
python -m pip install pandas openpyxl
```

Needed for one file only, the lender spreadsheet.

---

## Step 3. Set up the project folder

This holds the code. The data stays in Downloads.

```powershell
New-Item -ItemType Directory -Force "$HOME\projects\hmda-ny\migrations" | Out-Null
New-Item -ItemType Directory -Force "$HOME\projects\hmda-ny\seed" | Out-Null
New-Item -ItemType Directory -Force "$HOME\projects\hmda-ny\docs" | Out-Null
Set-Location "$HOME\projects\hmda-ny"

$out = "$HOME\Downloads\hmda_new_york_2022-2025\Claude outputs"
Copy-Item "$out\0*.sql"              ".\migrations\"
Copy-Item "$out\load_raw.ps1"        ".\seed\"
Copy-Item "$out\load_lender_file.py" ".\seed\"
Copy-Item "$out\column_mapping.md"   ".\docs\"
Remove-Item ".\migrations\02_ref_code.sql" -ErrorAction SilentlyContinue
```

That last line removes a duplicate. `02_ref_code.sql` and `002b_ref_code_seed.sql` are the same file, and leaving both would load the codes twice.

**Check it:**

```powershell
Get-ChildItem .\migrations | Select-Object Name
```

**You should see exactly these ten**, in this order:

```
000_raw_layer.sql
001_schemas.sql
002_dimensions.sql
002b_ref_code_seed.sql
003_fact.sql
004_bridges.sql
005_constraints_indexes.sql
006_quarantine_and_checks.sql
007_views.sql
008_assertions.sql
```

If `load_raw.ps1` in your `Claude outputs` folder is older than this guide, use the new one I sent with it. The old version tried to build a `data\` folder; the new one does not.

---

## Step 4. Create the database

```powershell
$env:PGPASSWORD = Read-Host "PostgreSQL password for postgres"
createdb -U postgres hmda
```

**You should see** no output. Silence means success.

If it says the database already exists and you want to start clean:

```powershell
dropdb -U postgres hmda
createdb -U postgres hmda
```

**Check it:**

```powershell
psql -U postgres -d hmda -c "SELECT version();"
```

**You should see** a line starting `PostgreSQL 18`.

---

## Step 5. Load the raw data

```powershell
.\seed\load_raw.ps1
```

If PowerShell blocks the script, allow it for this window only and try again:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\seed\load_raw.ps1
```

**First it checks every file exists** and prints a list with sizes. If anything is missing it stops there and names it, before touching the database. That check should show twelve CSVs plus the spreadsheet.

**Then it loads, taking about 2 minutes**, and prints row counts.

**The numbers that must match:**

| source | 2022 | 2023 | 2024 | 2025 |
|---|---|---|---|---|
| raw_lar | 549,677 | 391,574 | 383,614 | 430,554 |
| raw_ts | 4,484 | 5,129 | 4,926 | 4,782 |
| raw_msamd | 413 | 413 | 418 | 418 |
| raw_lender | 4,484 | 5,129 | 4,926 | 4,782 |

If a loan register count differs, that year's export used different Data Browser filters. It needs state = New York with no lender filter.

> If your files are somewhere other than `Downloads\hmda_new_york_2022-2025`, run it as
> `.\seed\load_raw.ps1 -DataDir "D:\wherever"`. If a filename differs from the table at the top of this guide, edit the `$Manifest` block at the top of `load_raw.ps1`. That block is the only place filenames appear.

---

## Step 6. Run the migrations

```powershell
Get-ChildItem .\migrations\*.sql | Sort-Object Name | ForEach-Object {
    Write-Host "== $($_.Name)" -ForegroundColor Cyan
    psql -U postgres -d hmda -v ON_ERROR_STOP=1 -q -f $_.FullName
    if ($LASTEXITCODE -ne 0) { Write-Host "FAILED at $($_.Name)" -ForegroundColor Red; break }
}
```

**This takes about 8 minutes.** Roughly six of those are `003_fact.sql`, which prints nothing at all while it builds 1.75 million rows. **That is normal. Do not interrupt it.**

**You should see** each filename in blue as it starts, some `NOTICE: table ... does not exist, skipping` lines on a first run which are harmless, and no `ERROR` lines.

Rough timings, so you know whether something has stalled:

| file | time |
|---|---|
| 000, 001, 002b | instant |
| 002_dimensions | 7 sec |
| **003_fact** | **6 min** |
| 004_bridges | 36 sec |
| 005_constraints_indexes | 23 sec |
| 006_quarantine_and_checks | 6 sec |
| 007, 008 | instant |

---

## Step 7. Check the build

```powershell
psql -U postgres -d hmda -c "SELECT * FROM marts.assert_failures;"
```

**You should see** `(0 rows)`. That is the test. Nothing failing means the build is correct.

Then the full picture:

```powershell
psql -U postgres -d hmda -c "SELECT assertion, severity, failing_rows, pct_of_fact, status FROM marts.assert_results ORDER BY failing_rows DESC;"
```

**You should see** eight rows: seven `pass`, and one reading

```
denial_reason_on_non_denial | source_defect | 27229 | 1.552 | known_issue_within_tolerance
```

That is not your build misbehaving. It is 167 lenders filing a denial reason on applications that were never denied, which is a finding rather than a fault.

---

## Step 8. Prove it matches mine

```powershell
psql -U postgres -d hmda -c "SELECT activity_year, applicant_race, round(100.0*count(*) FILTER (WHERE is_denied)/count(*) FILTER (WHERE is_decided),1) AS denial_rate FROM marts.v_application WHERE is_decided AND applicant_race IN ('White','Black or African American') GROUP BY 1,2 ORDER BY 1,2;"
```

**You should see** eight rows, starting:

```
2022 | Black or African American | 37.3
2022 | White                     | 21.0
```

If those two numbers come out right, your database is identical to mine and every figure I have quoted will reproduce on your machine. If they differ, stop and tell me what you got.

---

## Step 9. Switch to pgAdmin

The command line was only needed for the bulk load, because `\copy` is a psql feature pgAdmin cannot run. Now open pgAdmin, connect to the `hmda` database, and work there.

The three schemas:

- `raw` is as-downloaded, never edited
- `ref` holds the code labels and metadata
- `marts` is the model, and `marts.v_application` is the view that reads in plain English

---

## Optional cleanup

Once step 8 passes, these are safe to delete from the Downloads folder:

```powershell
Remove-Item "$HOME\Downloads\hmda_new_york_2022-2025\data" -Recurse -Force
Remove-Item "$HOME\Downloads\hmda_new_york_2022-2025\*.7z"
```

The `.7z` archives are just compressed copies of CSVs you have already extracted. **Keep the CSVs.** The loader reads them every time you rebuild.

---

## If something goes wrong

**`Cannot find <file> in <folder>`** — the loader's pre-flight check did its job. Either the file is somewhere else, or its name differs. Fix the `$Manifest` block at the top of `load_raw.ps1`.

**`password authentication failed`** — rerun `$env:PGPASSWORD = Read-Host "password"`.

**`extra data after last expected column`** — that CSV has more than 99 columns, so it came from the wrong export. Re-download that year from the Data Browser.

**`relation "raw.raw_lar" does not exist`** — step 5 did not finish. Run it again before step 6.

**Step 6 stops partway** — read the last `ERROR` line. Every migration drops and recreates what it owns, so once the cause is fixed you can safely run the whole loop again from the top. It costs you the 8 minutes, nothing else.

**Start completely over** — `dropdb -U postgres hmda`, then back to step 4.
