# playground

Builds a browser-runnable copy of the database. No server, no install, no account.

```
playground/
  export_parquet.py     PostgreSQL -> Parquet, with the column types preserved
  bootstrap.sql         recreates the marts / ref schemas and views over the Parquet
  queries/*.sql         the ten published analysis queries, portable dialect
  parity_test.py        runs all ten against both engines and fails on any difference
  page_template.html    the page; bootstrap.sql and queries/ are inlined at build time
  build_page.py         writes site/
  vendor_entry.js       esbuild entry point for the DuckDB WASM bundle
```

## Build it

Requires a built `hmda` database (see `../RUNBOOK.md`), Python with `duckdb`, and Node.

```bash
pip install duckdb --break-system-packages
npm install                  # pins duckdb-wasm 1.28.0, see package.json
npm run vendor               # -> vendor/  (the engine, 18 MB)
python3 export_parquet.py    # -> parquet/  (82 MB, 19 files)
python3 parity_test.py       # must print "all 10 queries return identical results"
python3 build_page.py        # -> ../docs/playground/  (index.html + vendor/ + data/)
```

`build_page.py` writes into `../docs/playground` by default, because GitHub Pages
serves the `docs` folder of the main branch with no build step. Pass a directory to
build somewhere else, for example `python3 build_page.py site` for local testing.

Serve it with any static server. One without HTTP range support works too: see
phase 10 section 5 for why that turns out not to matter here.

Step by step, including publishing it: [`../docs/DEPLOY_PLAYGROUND.md`](../docs/DEPLOY_PLAYGROUND.md).

## Why each piece exists

**`export_parquet.py` imposes types rather than inferring them.** A plain CSV round
trip lets DuckDB guess, and it guesses `BIGINT` for every HMDA code column because
codes look like numbers. In PostgreSQL `action_taken` is `text`, so the published
predicate is `action_taken IN ('1','3')`, which errors against an inferred integer
column. The script reads `information_schema` and applies those types, then checks
the result.

**`bootstrap.sql` recreates the schema names.** Without it every query would have to
be rewritten to read `'fct_application_2024.parquet'` instead of
`marts.fct_application`, and the repository would ship two versions of every query.

**`parity_test.py` is the point of the whole directory.** The claim is not "here is
some SQL and here is a browser database", it is "these queries return the same
numbers in both engines". Phase 10 section 3 has the difference that made this
necessary: PostgreSQL's `~` is a partial regex match and DuckDB's is a full match,
so one query silently returned 18,051 in one engine and 14,527 in the other.
