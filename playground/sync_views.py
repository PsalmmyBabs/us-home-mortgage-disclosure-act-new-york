#!/usr/bin/env python3
"""
Regenerate the labelled-view section of bootstrap.sql from the live database.

Why this exists. bootstrap.sql recreates the marts and ref namespaces over the
Parquet export so that the queries published in the analysis documents run in
the browser unchanged. The view definitions in it used to be written by hand,
and they drifted from migrations/007_views.sql without anyone noticing:

  v_denial_reason     joined code_field 'denial_reason', which does not exist,
                      so it returned no rows at all in the browser
  v_application       was missing eleven columns, including loan_type,
                      lien_status, applicant_age and is_purchased_loan
  v_application_race  joined code_field 'race' rather than 'applicant_race_1'

Nothing failed, because no published query used any of them. The playground
footer claimed the views matched PostgreSQL exactly, and they did not.

parity_test.py now compares each view's row count and shape across both engines
directly, so a view is checked whether or not a published query happens to read
from it. That is the part that was missing, not the definitions.

So the definitions are now read from pg_get_viewdef and written into
bootstrap.sql between the markers below. Run this after changing
migrations/007_views.sql, before build_page.py, then run parity_test.py.

Usage:  python3 sync_views.py
"""
import os
import pathlib
import re
import subprocess
import sys

VIEWS = ["v_application", "v_denial_reason", "v_application_race"]
BEGIN = "-- >>> GENERATED VIEWS BEGIN (sync_views.py)"
END = "-- <<< GENERATED VIEWS END"

PG = ["psql",
      "-h", os.environ.get("PGHOST", "localhost"),
      "-p", os.environ.get("PGPORT", "5432"),
      "-U", os.environ.get("PGUSER", "postgres"),
      "-d", os.environ.get("PGDATABASE", "hmda"),
      "-X", "-tA", "-q", "-v", "ON_ERROR_STOP=1"]
ENV = {**os.environ, "PGCLIENTENCODING": "UTF8"}


def viewdef(name):
    r = subprocess.run(PG + ["-c", f"SELECT pg_get_viewdef('marts.{name}'::regclass, true);"],
                       capture_output=True, text=True, env=ENV)
    if r.returncode:
        sys.exit(f"could not read marts.{name}: {r.stderr.strip()}")
    body = r.stdout.strip()
    if not body:
        sys.exit(f"marts.{name} does not exist")
    return body


def to_duckdb(sql):
    """PostgreSQL's printed form into DuckDB-accepted SQL.

    Two substitutions, neither of which changes meaning:
      ::text casts          removed, DuckDB infers the type
      = ANY (ARRAY[...])    rewritten as IN (...)
    If a future view needs more than this the script should fail loudly rather
    than ship a silently different view, so anything else is left untouched and
    the parity test is what catches it.
    """
    sql = sql.replace("::text", "")
    sql = re.sub(r"=\s*ANY\s*\(ARRAY\[(.*?)\]\)", r"IN (\1)", sql, flags=re.S)
    sql = re.sub(r"\n\s+", "\n       ", sql).strip()
    return sql.rstrip(";").rstrip()   # pg_get_viewdef already ends in ;


def main():
    path = pathlib.Path("bootstrap.sql")
    text = path.read_text()
    if BEGIN not in text or END not in text:
        sys.exit("bootstrap.sql is missing the generated-view markers")

    blocks = [f"CREATE OR REPLACE VIEW marts.{v} AS\n{to_duckdb(viewdef(v))};" for v in VIEWS]
    body = BEGIN + "\n" + "\n\n".join(blocks) + "\n" + END

    new = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), body, text, flags=re.S)
    if new == text:
        print("bootstrap.sql already matches the database")
    else:
        path.write_text(new)
        print(f"bootstrap.sql updated: {len(VIEWS)} views regenerated from pg_catalog")


if __name__ == "__main__":
    main()
