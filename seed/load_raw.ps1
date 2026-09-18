# =====================================================================
#  load_raw.ps1  -  loads the raw layer on Windows
#
#  Reads the downloaded CSVs where they already sit. Nothing is copied,
#  moved or renamed. If your files live somewhere else, change $DataDir
#  below or pass -DataDir when you run it.
#
#      .\seed\load_raw.ps1
#      .\seed\load_raw.ps1 -DataDir "D:\hmda" -Database hmda
# =====================================================================
param(
    [string]$DataDir  = "$HOME\Downloads\hmda_new_york_2022-2025",
    [string]$Database = "hmda",
    [string]$PgBin    = "C:\Program Files\PostgreSQL\18\bin",
    [string]$PgUser   = "postgres"
)

$ErrorActionPreference = "Stop"
$psql = Join-Path $PgBin "psql.exe"

# ---------------------------------------------------------------------
# The manifest. One line per year naming the three files exactly as they
# were downloaded. This is the only part to edit if a filename differs.
# ---------------------------------------------------------------------
$Manifest = @(
    @{ Year = 2022
       Lar   = "hmda_new_york_2022_three_years.csv"
       Ts    = "2022_transmittal_sheet.csv"
       Msamd = "2022_msamd.csv" },
    @{ Year = 2023
       Lar   = "hmda_new_york_2023_one_year.csv"
       Ts    = "2023_transmittal_sheet.csv"
       Msamd = "2023_msamd.csv" },
    @{ Year = 2024
       Lar   = "hmda_new_york_2024_one_year.csv"
       Ts    = "2024_transmittal_sheet.csv"
       Msamd = "2024_msamd.csv" },
    @{ Year = 2025
       Lar   = "state_NY.csv"
       Ts    = "hmda_institution_names.csv"
       Msamd = "hmda_msamd.csv" }
)
$LenderFile = "hmda_lender_file.xlsx"

# ---------------------------------------------------------------------
if (-not (Test-Path $psql)) {
    Write-Host "Could not find psql.exe at $psql" -ForegroundColor Red
    Write-Host "Check your PostgreSQL version folder and pass it with -PgBin"
    exit 1
}

function Invoke-Psql {
    param([string]$Sql, [string]$File)
    if ($File) { & $psql -U $PgUser -d $Database -v ON_ERROR_STOP=1 -q -f $File }
    else       { & $psql -U $PgUser -d $Database -v ON_ERROR_STOP=1 -q -c $Sql }
    if ($LASTEXITCODE -ne 0) { throw "psql failed" }
}

function Resolve-Data {
    param([string]$Name)
    $p = Join-Path $DataDir $Name
    if (-not (Test-Path $p)) { throw "Cannot find $Name in $DataDir" }
    return ($p -replace '\\', '/')
}

# ---------------------------------------------------------------------
# Check everything is present BEFORE touching the database, so a missing
# file is reported in one go instead of halfway through a 700 MB load.
# ---------------------------------------------------------------------
Write-Host "==> checking source files in $DataDir" -ForegroundColor Cyan
$missing = @()
foreach ($y in $Manifest) {
    foreach ($f in $y.Lar, $y.Ts, $y.Msamd) {
        if (Test-Path (Join-Path $DataDir $f)) {
            $mb = [math]::Round((Get-Item (Join-Path $DataDir $f)).Length / 1MB, 1)
            Write-Host ("    {0}  {1,8} MB  {2}" -f $y.Year, $mb, $f)
        } else {
            $missing += $f
        }
    }
}
if (Test-Path (Join-Path $DataDir $LenderFile)) {
    Write-Host ("    all   {0,8} MB  {1}" -f [math]::Round((Get-Item (Join-Path $DataDir $LenderFile)).Length/1MB,1), $LenderFile)
} else { $missing += $LenderFile }

if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing files:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "    $_" }
    Write-Host "Edit the `$Manifest block at the top of this script to match your filenames."
    exit 1
}

# ---------------------------------------------------------------------
Write-Host ""
Write-Host "==> creating the raw layer" -ForegroundColor Cyan
Invoke-Psql -File "migrations\000_raw_layer.sql"

foreach ($y in $Manifest) {
    Write-Host "==> $($y.Year) loan application register" -ForegroundColor Cyan
    Invoke-Psql "\copy raw.raw_lar FROM '$(Resolve-Data $y.Lar)' WITH (FORMAT csv, HEADER true)"

    Write-Host "==> $($y.Year) transmittal sheet" -ForegroundColor Cyan
    Invoke-Psql "\copy raw.raw_ts FROM '$(Resolve-Data $y.Ts)' WITH (FORMAT csv, HEADER true)"

    Write-Host "==> $($y.Year) MSA descriptions" -ForegroundColor Cyan
    Invoke-Psql "\copy raw.raw_msamd (msa_md, msa_md_name, state) FROM '$(Resolve-Data $y.Msamd)' WITH (FORMAT csv, HEADER true)"
    Invoke-Psql "UPDATE raw.raw_msamd SET activity_year = $($y.Year) WHERE activity_year IS NULL;"
}

Write-Host "==> Philadelphia Fed lender file" -ForegroundColor Cyan
python "seed\load_lender_file.py" (Join-Path $DataDir $LenderFile) $Database
if ($LASTEXITCODE -ne 0) { throw "lender file load failed" }

Write-Host ""
Write-Host "==> row counts" -ForegroundColor Cyan
Invoke-Psql @"
SELECT 'raw_lar' AS source, activity_year AS year, count(*) FROM raw.raw_lar GROUP BY 1,2
UNION ALL SELECT 'raw_ts', activity_year, count(*) FROM raw.raw_ts GROUP BY 1,2
UNION ALL SELECT 'raw_msamd', activity_year::text, count(*) FROM raw.raw_msamd GROUP BY 1,2
UNION ALL SELECT 'raw_lender', year, count(*) FROM raw.raw_lender GROUP BY 1,2
ORDER BY 1,2;
"@

Write-Host ""
Write-Host "Expected:" -ForegroundColor Green
Write-Host "  raw_lar     2022 549,677   2023 391,574   2024 383,614   2025 430,554"
Write-Host "  raw_ts      2022   4,484   2023   5,129   2024   4,926   2025   4,782"
Write-Host "  raw_msamd   2022     413   2023     413   2024     418   2025     418"
Write-Host "  raw_lender  2022   4,484   2023   5,129   2024   4,926   2025   4,782"
Write-Host ""
Write-Host "Next: step 6 in SETUP_WINDOWS.md (run the migrations)."
