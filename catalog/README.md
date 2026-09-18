# catalog

Generates the data dictionary at `docs/catalog/index.html` from the live PostgreSQL
catalogue.

```
catalog/
  build_catalog.py    reads pg_catalog, writes one self-contained HTML file
```

## Build it

```bash
python3 build_catalog.py              # -> ../docs/catalog/index.html
python3 build_catalog.py out          # or anywhere else
```

Needs `psql` on the PATH and the same `PG*` environment variables as the playground.
Takes about two seconds and produces roughly 90 kB with no external assets, so it works
from GitHub Pages, from a `file://` URL and offline.

## The design decision worth defending

**Nothing in the page is hand-written.** Tables, columns, types, nullability, defaults,
keys, foreign keys, check constraints, indexes with their definitions and sizes,
partitions with their bounds, inbound references and exact row counts all come from
`pg_catalog` at build time. The prose comes from `COMMENT ON` statements in
`migrations/009_comments.sql`.

That is the whole point. A data dictionary maintained as a separate document starts
drifting from the schema within a quarter and is quietly wrong within a year. This one
cannot describe a column that no longer exists, because it does not know about any
column the database does not have. And because the descriptions live in the catalogue
rather than in a wiki, they are versioned with the DDL, reviewable in the same diff, and
visible to anyone connected to the database:

```sql
\d+ marts.fct_application
SELECT col_description('marts.fct_application'::regclass, 12);
```

The build reports coverage and names every table column with no comment, so an
undocumented column is a visible number rather than something nobody notices. It
currently reports 100 percent of 175 table columns.

Coverage is measured over table columns only. A view column inherits its meaning from
the column it selects, so requiring a separate comment there would mean maintaining the
same sentence in two places, which is the failure mode this whole approach avoids.

## What it does that the usual schema exporters do not

| | |
|---|---|
| One page, not a frameset | Deep links work: `#marts.fct_application` opens that table |
| Column search across every table | Type `lei` to find all five tables that carry it |
| Foreign keys are links | And each table lists what references it, not only what it references |
| Index definitions and sizes | Including which are partial and which are unique |
| Partition bounds | So the year-per-partition design is visible |
| Exact row counts | Not `reltuples` estimates |
| Dark mode, and usable on a phone | Because a reviewer may open it from a message |

## Regenerating

Run it after any migration that adds, removes or renames a column, then commit the
result. It is 90 kB of text, so it diffs cleanly and costs nothing in the repository.
