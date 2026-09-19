# Phase 10: The browser playground

The problem this project started from: a SQL portfolio on GitHub is a folder of `.sql` files that nobody can run. This phase makes the database itself openable in a browser tab, with the published queries returning the published numbers.

Previous phase: [09 Performance tuning](09_performance_tuning.md) · Back to [the README](../README.md)

---

## 1. What a reviewer can actually do

Open the page. After the load described in section 5, there is a dropdown with the ten queries from phase 08, an editable SQL box, and 1,754,846 rows of real mortgage data in fifteen tables. Every query runs inside the tab. Nothing is installed, no account exists, no data leaves the machine, and there is no server to keep running or pay for.

Measured on the built site, all ten published queries:

| query | rows | time |
|---|---|---|
| 01 denial by year | 4 | 99 ms |
| 02 outcome mix | 8 | 215 ms |
| 03 denial by group | 9 | 145 ms |
| 04 gap within income | 5 | 198 ms |
| 05 shift share | 1 | 387 ms |
| 06 within tract | 1 | 819 ms |
| 07 lender spread | 1 | 593 ms |
| 08 race rollup trap | 1 | 1,618 ms |
| 09 incompleteness channel | 21 | 335 ms |
| 10 reconciliation | 1 | 17 ms |

The slowest is 1.6 seconds and it is aggregating 3.66 million bridge rows. In a browser tab.

---

## 2. How it is put together

| piece | choice | why |
|---|---|---|
| engine | DuckDB compiled to WebAssembly | a real analytical SQL engine, columnar, runs client side |
| data format | Parquet, zstd compressed, 19 files, 82 MB | compresses 2.4 GB of PostgreSQL to 82 MB and reads columns selectively |
| fact layout | one file per year | mirrors the PostgreSQL partitioning, so the layout is the same idea in both places |
| schema | `bootstrap.sql` recreates `marts` and `ref` as views | the published queries run unedited |
| hosting | GitHub Pages, static files | free, no server, same origin as the data |
| engine delivery | vendored into the repo, not a CDN | no third-party dependency at run time |

The build is four commands, and the second one is the interesting one:

```bash
python3 export_parquet.py    # PostgreSQL -> Parquet, types preserved
python3 parity_test.py       # both engines must agree, or the build fails
npm run build                # bundle the engine, write site/
# publish site/
```

---

## 3. The bug that justifies the parity test

The whole claim of this phase is that the SQL in phase 08 is the SQL that runs in the browser. That claim is easy to make and easy to break, because the two engines disagree in places where **neither of them raises an error**.

Phase 06 has a query that counts multi-race applicants after rolling HMDA's hierarchical race codes up to their top-level parent. It was written like this:

```sql
WHERE race_code ~ '^[1-5]'
```

| engine | result |
|---|---|
| PostgreSQL | 18,051 |
| DuckDB | **14,527** |

No error. No warning. A 20 percent difference in a published figure.

The cause: **PostgreSQL's `~` is a partial regex match and DuckDB's is a full match.** In PostgreSQL, `'22' ~ '^[1-5]'` is true, because the pattern matches somewhere in the string. In DuckDB the same expression is false, because `^[1-5]` has to match the entire string and `'22'` is two characters long.

```
duckdb:    SELECT '22' ~ '^[1-5]';                  -- false
duckdb:    SELECT regexp_matches('22', '^[1-5]');   -- true
postgres:  SELECT '22' ~ '^[1-5]';                  -- true
```

`regexp_matches` is not the fix, because in PostgreSQL it returns a set of text arrays rather than a boolean, so it cannot be dropped into a `WHERE` clause. The portable form is the one that needed no regex in the first place:

```sql
WHERE left(race_code, 1) IN ('1','2','3','4','5')
```

Which means the same thing in both engines, returns 18,051 in both, and is clearer than what it replaced.

A second difference, which at least fails loudly:

```sql
round(percentile_cont(0.5) WITHIN GROUP (ORDER BY spread), 1)
-- postgres: ERROR: function round(double precision, integer) does not exist
-- duckdb:   works
```

`percentile_cont` returns a double, and PostgreSQL only has `round(numeric, int)`. The portable form is `round(CAST(... AS numeric), 1)`, which both accept.

**So the repository runs a parity test rather than trusting the claim.** `parity_test.py` executes every file in `queries/` against both engines, normalises the output, and exits non-zero on any difference:

```
  ok     01_denial_by_year.sql  (4 rows)
  ok     02_outcome_mix.sql  (8 rows)
  ...
  ok     10_reconciliation.sql  (1 rows)

all 10 queries return identical results in both engines
```

That output is what makes the playground trustworthy. Without it, "the same queries run here" is a hope.

---

## 4. Type fidelity, which is the other way this breaks

The export has to preserve types, not re-infer them. Read the CSVs back without saying what the columns are and DuckDB reasonably concludes that `action_taken` is a `BIGINT`, because every value in it looks like a number:

```
action_taken -> BIGINT       -- inferred
action_taken -> VARCHAR      -- what PostgreSQL actually has
```

At which point `action_taken IN ('1','3')` errors, `ref_code.code_value = f.action_taken` errors because one side is text and the other is not, and every query in phase 08 has to be rewritten for the browser. The portability claim dies quietly.

So `export_parquet.py` reads the real types out of the catalogue and imposes them:

```python
rows = psql(f"""SELECT column_name, data_type FROM information_schema.columns
                WHERE table_schema = '{schema}' AND table_name = '{table}'
                ORDER BY ordinal_position""")
```

then asserts that the thing it exists to protect actually holds:

```
type fidelity check: action_taken IN ('1','3') matched 283,192 rows
```

283,192 is the same number PostgreSQL gives for 2024 decided applications, so the round trip preserved both the type and the data.

The compression is worth stating too. 2.4 GB of PostgreSQL becomes **82 MB of Parquet**, a 29 times reduction, because Parquet stores columns rather than rows and a column of repeated HMDA codes compresses to almost nothing. The `raw` schema and the indexes are not exported, which accounts for most of it, but the fact table alone goes from 676 MB across four partitions to 70 MB.

---

## 5. The range-request idea that measured worse

DuckDB-WASM can read a Parquet file over HTTP with range requests, fetching only the row groups a query needs. This is the feature everyone cites when recommending this architecture, and it is why the fact table is split into one file per year.

It is controlled by one boolean, the `directIO` argument:

```js
await db.registerFileURL(name, url, duckdb.DuckDBDataProtocol.HTTP, /* directIO */ true);
```

Measured on a local server with range support, one year-filtered count:

| `directIO` | behaviour | data fetched for one query |
|---|---|---|
| `true` | HTTP range requests, read only what is needed | **142 MB** |
| `false` | buffer each file once on first touch | 0 MB |

The range-request version fetched 142 MB to answer a query against 82 MB of data, because DuckDB-WASM does not cache what it reads through range requests. Each row group it needs is re-fetched, and a query that visits the same data twice pays twice. The buffered version had already downloaded the files at startup and answered from memory.

So the playground ships with `directIO: false`, which is the opposite of what the feature exists for, and the comment in the code says why. The honest full accounting:

| | size | when |
|---|---|---|
| page | 25 kB | at load |
| DuckDB engine, WebAssembly | 17.7 MB | at load |
| Parquet data | 83.8 MB | at load |
| all ten queries afterwards | 23 MB total, 0 to 8.5 MB each | as run |

About 125 MB for a visitor who loads the page and runs everything. On a 50 Mbit connection that is roughly 20 seconds of downloading, once, and then a local analytical database that answers in milliseconds. On the local test server the page was ready in 1.0 second.

**A stated trade-off not taken.** The fact table is 70 of the 82 MB and carries about 40 columns. Exporting only the 17 columns the published queries use shrinks one year from 15.8 MB to 6.1 MB, which would bring the whole dataset to roughly 39 MB. It is not done, because a playground where a reviewer can only run the queries I wrote is worth much less than one where they can explore the model I claim to have built. The number is here so the choice is visible rather than assumed.

---

## 6. Two more things that had to be measured rather than assumed

**The engine version matters.** DuckDB-WASM 1.29.0 made the Parquet reader a dynamically loaded extension, so the page tries to fetch `extensions.duckdb.org/v1.1.1/wasm_eh/parquet.duckdb_extension.wasm` at startup and dies with `table index is out of bounds` if that host is unreachable. 1.28.0 links Parquet statically. The version is pinned in `package.json` with that reason written next to it, because "upgrade to the latest" would silently reintroduce a network dependency and an unhelpful error message.

The older build is also half the size: 18 MB of WebAssembly against 35 MB.

**Relative paths do not work for the worker.** The engine's worker script resolves `mainModule` against its own location, not the page's, so `./vendor/duckdb-eh.wasm` becomes `/vendor/vendor/duckdb-eh.wasm` and 404s. The bundle config uses absolute URLs built from `location.href`. This took a headless browser and a 404 log to find, and no amount of reading the page source would have shown it.

---

## 7. What was rejected

| option | why not |
|---|---|
| A hosted PostgreSQL with a public read-only user | costs money, needs maintenance, and dies the day the free tier changes |
| A screenshot of results in the README | proves nothing, and is exactly the problem this phase exists to solve |
| A Jupyter notebook on Binder | cold starts of minutes, frequent queue failures, and it is Python rather than SQL |
| Loading the CSVs directly in the browser | 638 MB against 82 MB, and no column pruning |
| PGlite, PostgreSQL compiled to WASM | genuinely the same dialect, but single threaded with no columnar execution, so the 3.66 million row bridge aggregates are not viable |
| DuckDB-WASM from a CDN | smaller repository, but a run-time dependency on a third party for something meant to still work in five years |
| Hive-partitioned paths with a glob | DuckDB-WASM cannot glob over HTTP, so the files have to be listed, which is what `bootstrap.sql` does |

The PGlite line is the one worth expanding, because it was the closer call. PGlite would have removed this entire phase's dialect problem: same engine, same `~` operator, no parity test needed. It loses on execution model. DuckDB is a columnar vectorised engine and PGlite is single-threaded row-at-a-time PostgreSQL in WASM, and the queries here aggregate millions of rows. The dialect gap was the cheaper problem to solve, and solving it produced the parity test, which is a better artefact than the problem it fixed.

---

## 8. What is worth defending in a review

| choice | the alternative | why this one |
|---|---|---|
| DuckDB-WASM | PGlite, same dialect | columnar execution is what makes 3.66 million row aggregates viable in a tab |
| A parity test in the repository | trusting that the SQL is portable | one silent regex difference changed a published figure by 20 percent |
| Types read from `information_schema` | let the CSV reader infer | inferred `BIGINT` codes break every published query |
| `bootstrap.sql` recreating `marts` and `ref` | rewrite the queries for Parquet paths | one version of every query, not two |
| `directIO: false` | HTTP range requests | measured: 142 MB per query against 0 |
| Engine vendored, version pinned | CDN, latest version | 1.29.0 needs a network fetch to read Parquet at all |
| Ship all 40 fact columns | 17 columns and half the download | a playground you can only run my queries in is worth much less |
| Static files on GitHub Pages | a hosted database | nothing to pay for and nothing to keep alive |
