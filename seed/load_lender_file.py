#!/usr/bin/env python3
"""
Loads the Philadelphia Fed HMDA Lender File (the "Avery file") into
raw.raw_lender, filtered to the years this project uses.

It is a spreadsheet rather than a CSV, and its column list can change
between releases, so the table is created from the file's own header
instead of being hard-coded. Everything is loaded as text; casting
happens in migrations/002_dimensions.sql like every other source.

Usage:  python3 seed/load_lender_file.py data/lender_file.xlsx [database]
"""
import subprocess
import sys
import tempfile

import pandas as pd

YEARS = [2022, 2023, 2024, 2025]
SHEET = "beta3"          # the Fed's current sheet name; check if this fails


def main(path: str, database: str = "hmda") -> None:
    frame = pd.read_excel(path, sheet_name=SHEET)
    frame.columns = [c.strip().lower() for c in frame.columns]
    frame = frame[frame["year"].isin(YEARS)]
    print(f"    {len(frame):,} lender-year rows for {YEARS}")

    columns = ",\n  ".join(f'"{c}" text' for c in frame.columns)
    ddl = (
        "CREATE SCHEMA IF NOT EXISTS raw;\n"
        "DROP TABLE IF EXISTS raw.raw_lender CASCADE;\n"
        f"CREATE TABLE raw.raw_lender (\n  {columns}\n);"
    )

    with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False) as handle:
        frame.to_csv(handle.name, index=False)
        csv_path = handle.name

    run = lambda *args: subprocess.run(
        ["psql", "-d", database, "-v", "ON_ERROR_STOP=1", "-q", *args], check=True
    )
    run("-c", ddl)
    run("-c", f"\\copy raw.raw_lender FROM '{csv_path}' WITH (FORMAT csv, HEADER true)")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "hmda")
