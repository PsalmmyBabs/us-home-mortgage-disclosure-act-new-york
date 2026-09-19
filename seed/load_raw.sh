#!/usr/bin/env bash
# =====================================================================
# Loads the raw layer. Run this AFTER migrations/000_raw_layer.sql and
# BEFORE migrations/001_schemas.sql.
#
# Expects this folder layout, one subfolder per filing year:
#
#   data/
#   ├── 2022/  state_NY.csv  transmittal_sheet.csv  msamd.csv
#   ├── 2023/  state_NY.csv  transmittal_sheet.csv  msamd.csv
#   ├── 2024/  state_NY.csv  transmittal_sheet.csv  msamd.csv
#   ├── 2025/  state_NY.csv  transmittal_sheet.csv  msamd.csv
#   └── lender_file.xlsx          (Philadelphia Fed, covers 2018-2025)
#
# The LAR files come from the HMDA Data Browser filtered to New York with
# no LEI filter. The transmittal sheet and MSA files come from the
# publication page matching that year's vintage (three-year for 2022,
# one-year for 2023 and 2024, snapshot for 2025).
#
# Usage:  ./seed/load_raw.sh [data_dir] [database]
# =====================================================================
set -euo pipefail

DATA_DIR="${1:-./data}"
DB="${2:-hmda}"
PSQL="psql -d ${DB} -v ON_ERROR_STOP=1 -q"

echo "==> creating raw layer"
${PSQL} -f migrations/000_raw_layer.sql

for YEAR in 2022 2023 2024 2025; do
  DIR="${DATA_DIR}/${YEAR}"
  [ -d "${DIR}" ] || { echo "missing ${DIR}, skipping"; continue; }

  echo "==> ${YEAR}: loan application register"
  ${PSQL} -c "\copy raw.raw_lar FROM '${DIR}/state_NY.csv' WITH (FORMAT csv, HEADER true)"

  echo "==> ${YEAR}: transmittal sheet"
  ${PSQL} -c "\copy raw.raw_ts FROM '${DIR}/transmittal_sheet.csv' WITH (FORMAT csv, HEADER true)"

  echo "==> ${YEAR}: MSA descriptions"
  ${PSQL} -c "\copy raw.raw_msamd (msa_md, msa_md_name, state) FROM '${DIR}/msamd.csv' WITH (FORMAT csv, HEADER true)"
  ${PSQL} -c "UPDATE raw.raw_msamd SET activity_year = ${YEAR} WHERE activity_year IS NULL;"
done

echo "==> Philadelphia Fed lender file"
python3 seed/load_lender_file.py "${DATA_DIR}/lender_file.xlsx" "${DB}"

echo "==> row counts"
${PSQL} -c "
SELECT 'raw_lar' AS table_name, activity_year, count(*) FROM raw.raw_lar GROUP BY 1,2
UNION ALL SELECT 'raw_ts', activity_year, count(*) FROM raw.raw_ts GROUP BY 1,2
UNION ALL SELECT 'raw_msamd', activity_year::text, count(*) FROM raw.raw_msamd GROUP BY 1,2
UNION ALL SELECT 'raw_lender', year, count(*) FROM raw.raw_lender GROUP BY 1,2
ORDER BY 1,2;"

cat <<'EOF'

Expected for New York, all lenders:

  raw_lar     2022  549,677    raw_ts  2022  4,484    raw_msamd  2022  413
              2023  391,574            2023  5,129               2023  413
              2024  383,614            2024  4,926               2024  418
              2025  430,554            2025  4,782               2025  418

  raw_lender  4,484 / 5,129 / 4,926 / 4,782 per year

If your counts differ, your Data Browser filters differ from the ones
used here. Re-export with state = New York and no lender filter.

Next:  psql -d hmda -f migrations/001_schemas.sql   (and so on, in order)
EOF
