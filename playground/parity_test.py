#!/usr/bin/env python3
"""
Parity test: run every query in queries/ against PostgreSQL and against the
Parquet export in DuckDB, and fail if any answer differs.

This exists because the playground's promise is specific. It is not "here is
some SQL and here is a browser database". It is "the queries published in
docs/08_analysis.md return the same numbers in both engines". That promise is
easy to make and easy to break silently, because the two engines disagree in
places where neither raises an error.

The difference that motivated this script: PostgreSQL's ~ operator is a
PARTIAL regex match, DuckDB's is a FULL match. So

    WHERE race_code ~ '^[1-5]'

selects 18,051 applications in PostgreSQL and 14,527 in DuckDB. No error, no
warning, a 20 percent difference in a published figure. The queries are now
written with left(race_code,1) IN (...) instead, which means the same thing in
both engines, and this script is what stops the next such difference shipping.

Usage:  python3 parity_test.py          exit code 0 means every query agrees
"""
import glob
import os
import pathlib
import subprocess
import sys

import duckdb

PGHOST = os.environ.get("PGHOST", "localhost")
PGPORT = os.environ.get("PGPORT", "5432")
PGUSER = os.environ.get("PGUSER", "postgres")
PGDB = os.environ.get("PGDATABASE", "hmda")

# psql takes its client encoding from the console codepage, usually WIN1252 on
# Windows, and some institution names carry characters it cannot represent.
ENV = {**os.environ, "PGCLIENTENCODING": "UTF8"}

# Floating point arithmetic differs in the last bits between engines, so
# numeric cells are compared to this many decimal places rather than exactly.
DECIMALS = 6


def run_postgres(sql):
    out = subprocess.run(
        ["psql", "-h", PGHOST, "-p", PGPORT, "-U", PGUSER, "-d", PGDB,
         "-X", "-A", "-t", "-F", "\x1f", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
        capture_output=True, text=True, env=ENV)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip())
    return [line.split("\x1f") for line in out.stdout.strip().splitlines() if line]


def run_duckdb(con, sql):
    return [[("" if v is None else str(v)) for v in row]
            for row in con.execute(sql).fetchall()]


def normalise(rows):
    """Make two result sets comparable: round numbers, blank out NULL spellings."""
    out = []
    for row in rows:
        cells = []
        for v in row:
            v = v.strip()
            if v in ("", "None", "NULL"):
                cells.append("")
                continue
            try:
                cells.append(f"{round(float(v), DECIMALS):.{DECIMALS}f}")
            except ValueError:
                cells.append(v)
        out.append(cells)
    return out


def load_bootstrap(con):
    """Create the marts / ref views over the local Parquet export.

    bootstrap.sql points at data/, which is where build_page.py puts the files
    in the published site. Before that build they are still in parquet/, so the
    paths are rewritten here. Keeping one bootstrap.sql rather than two is the
    whole point: the views the test checks are the views the site serves.
    """
    sql = pathlib.Path("bootstrap.sql").read_text()
    if not pathlib.Path("parquet").is_dir():
        sys.exit("no parquet/ directory. Run export_parquet.py first.")
    con.execute(sql.replace("'data/", "'parquet/").replace('"data/', '"parquet/'))


def main():
    con = duckdb.connect()
    load_bootstrap(con)

    files = sorted(glob.glob("queries/*.sql"))
    if not files:
        sys.exit("no queries found in queries/")

    failures = []
    for path in files:
        sql = open(path).read()
        name = os.path.basename(path)
        try:
            pg = normalise(run_postgres(sql))
        except RuntimeError as e:
            failures.append((name, f"postgres error: {e}"))
            print(f"  ERROR  {name}  (postgres)")
            continue
        try:
            dk = normalise(run_duckdb(con, sql))
        except Exception as e:
            failures.append((name, f"duckdb error: {str(e).splitlines()[0]}"))
            print(f"  ERROR  {name}  (duckdb)")
            continue

        if pg == dk:
            print(f"  ok     {name}  ({len(pg)} rows)")
        else:
            print(f"  DIFFER {name}  (postgres {len(pg)} rows, duckdb {len(dk)} rows)")
            for i, (a, b) in enumerate(zip(pg, dk)):
                if a != b:
                    failures.append((name, f"row {i+1}: postgres {a} vs duckdb {b}"))
                    break
            else:
                failures.append((name, "row counts differ"))

    print()
    if failures:
        print(f"{len(failures)} of {len(files)} queries do not agree:\n")
        for name, detail in failures:
            print(f"  {name}: {detail}")
        sys.exit(1)
    print(f"all {len(files)} queries return identical results in both engines")


if __name__ == "__main__":
    main()
