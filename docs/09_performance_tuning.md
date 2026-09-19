# Phase 09: Performance tuning

Six measurements on a 1.75 million row model. Two of them show an index I built being ignored by the planner, and 125 MB of indexes that should never have existed. Both are fixed in `005_constraints_indexes.sql` and both are kept in this document.

Previous phase: [08 The analysis](08_analysis.md) · Next phase: [10 The browser playground](10_playground.md)

---

## 1. How these numbers were produced

Every figure below is from `EXPLAIN (ANALYZE, BUFFERS)` on the real database, not from an estimate. Three rules, because timing a database badly is easy:

1. **Every query is run at least three times** and the last timing is reported. The first run reads from disk, later runs read from the buffer cache, and a cold first run has made more than one tuning claim in this project look backwards. Section 3 has an example.
2. **Buffers are reported alongside time.** Time depends on what else the machine is doing. Buffer counts do not, so they are the more honest measure of whether a plan got better.
3. **Baselines are forced, not imagined.** To measure what an index is worth, the alternative is produced with `SET enable_indexscan = off` rather than by dropping the index and rebuilding it.

Server: PostgreSQL 16.13, `shared_buffers` 128 MB, `work_mem` 4 MB, `max_parallel_workers_per_gather` 2. Deliberately a modest configuration, because a tuning result on a machine with more RAM than data proves nothing.

Current footprint:

| | size |
|---|---|
| whole database | 2,399 MB |
| `marts` | 1,682 MB |
| `raw` | 708 MB |
| `ref` | 184 kB |

---

## 2. Partition pruning, which is the cheapest win in the model

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM marts.fct_application WHERE activity_year = 2024;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM marts.fct_application;
```

| | partitions scanned | buffers | time |
|---|---|---|---|
| one year | 1 | 5,773 | **32.4 ms** |
| all four years | 4, via `Parallel Append` | 20,176 | 180.5 ms |

The pruned plan reads a quarter of the buffers and runs 5.6 times faster, and the plan text says so explicitly: one `Parallel Index Only Scan on fct_application_2024` against a `Parallel Append` over four children.

This costs nothing to obtain. It is a consequence of the phase 05 decision to partition by `activity_year`, and it applies to almost every query in phase 08, because almost every one of them is about a year.

---

## 3. Where the first cold run lied to me

The lender-versus-market query from phase 08 section 9 filters on `lei`, which is what `idx_fct_lender_tract (lei, census_tract)` exists for.

```sql
SELECT census_tract, count(*) FROM marts.fct_application
WHERE lei = '7H6GLXDRUGQFU57RNE97' GROUP BY 1;
```

The first measurement said the index made it **slower**: 569 ms with the index against 442 ms without. Which is true, and meaningless, because the index-only scan was reading 900 random pages off disk for the first time while the sequential scan was streaming.

Run each three times:

| | buffers | warm time |
|---|---|---|
| index only scan on `(lei, census_tract)` | 1,165 | **28.1 ms** |
| forced sequential scan | 53,416 | 142.5 ms |

46 times fewer buffers and 5.1 times faster. The index is doing exactly what it was built for. Reporting the cold number would have produced a confident, published, wrong conclusion, which is the same failure mode as the shift-share prediction in phase 08 and worth naming twice.

---

## 4. The index I got wrong

Phase 05 built a partial index for the dominant fairness query:

```sql
CREATE INDEX idx_fct_decided ON marts.fct_application (activity_year, applicant_profile_sk)
  WHERE action_taken IN ('1','3');
```

The reasoning was sound. Nearly every analysis query carries `action_taken IN ('1','3')`, so index only those rows. Then I ran the dominant query against it:

```sql
SELECT f.applicant_profile_sk, count(*) AS dec,
       count(*) FILTER (WHERE f.action_taken='3') AS den
FROM marts.fct_application f
WHERE f.activity_year = 2024 AND f.action_taken IN ('1','3')
GROUP BY 1;
```

```
->  Parallel Seq Scan on fct_application_2024 f (actual rows=94397 loops=3)
      Filter: ((action_taken = ANY ('{1,3}'::text[])) AND (activity_year = 2024))
Execution Time: 68.8 ms
```

**A sequential scan.** The index is not in the plan at all, and forcing the planner to ignore indexes entirely changes nothing: 67.1 ms. The index was 2,032 kB of dead weight.

The planner is right and I was wrong, for a reason worth understanding. The query needs `count(*) FILTER (WHERE action_taken = '3')`, and `action_taken` is in the index's **predicate** but not its **key**. The predicate tells the planner which rows are in the index. It does not let the planner read a row's `action_taken` value out of the index. So any plan using this index has to visit the heap for 94,397 rows to find out which of them were denials, and once you are visiting 74 percent of a partition's rows the sequential scan wins by a mile.

The fix is one column:

```sql
CREATE INDEX idx_fct_decided ON marts.fct_application
  (activity_year, applicant_profile_sk, action_taken)
  WHERE action_taken IN ('1','3');
```

| | plan | buffers | warm time |
|---|---|---|---|
| two column index | Parallel Seq Scan, index unused | 11,645 | 68.8 ms |
| three column index | **Parallel Index Only Scan** | 3,805 | **29.7 ms** |

2.3 times faster, 3 times fewer buffers, and the index grows from 2,032 kB to 2,128 kB. **96 kB per partition buys a doubling on the query this model exists to answer.**

The lesson generalises: a partial index restricts which rows are present, a covering index adds columns so the heap does not have to be touched, and they are different tools. If a column appears in the `SELECT` list, in a `FILTER`, or in an aggregate, it belongs in the key even when the `WHERE` clause already pins it down.

### 4.1 Where the partial index does earn its keep

The same index, on a selective query rather than an aggregate:

```sql
SELECT count(*) FROM marts.fct_application
WHERE activity_year = 2024 AND applicant_profile_sk = 1000 AND action_taken IN ('1','3');
```

```
Index Only Scan using ..._activity_year_applicant_profile_sk_act_idx
  Heap Fetches: 0
Buffers: shared hit=1 read=3
Execution Time: 0.477 ms
```

Against a forced sequential scan: 11,651 buffers and 35.7 ms. So **4 buffers against 11,651, and 75 times faster.** `Heap Fetches: 0` is the line to point at: the answer came entirely from the index and the table was never read.

Both results are the same index. One query gets 75x and the other gets nothing. That is why "add an index" is not a tuning strategy and a measured plan is.

---

## 5. 125 MB of indexes that should never have existed

`pg_stat_user_indexes` on the four bridge tables:

| index | size | scans |
|---|---|---|
| `br_application_race_pkey` | 189 MB | 0 |
| `br_application_ethnicity_pkey` | 186 MB | 0 |
| `idx_br_race_app` | 84 MB | 0 |
| `br_underwriting_system_pkey` | 42 MB | 0 |
| `idx_br_aus_app` | 29 MB | 0 |
| `br_denial_reason_pkey` | 17 MB | 0 |
| `idx_br_race_code` | 12 MB | 0 |
| `idx_br_denial_app` | 12 MB | 0 |

`br_application_race` is a 239 MB table carrying 285 MB of indexes. Look at what three of them are:

```
br_application_race_pkey  (activity_year, application_sk, party, slot)
idx_br_race_app           (activity_year, application_sk)
```

`idx_br_race_app` is an exact leading prefix of the primary key. A b-tree on `(a, b, c, d)` already serves every lookup that a b-tree on `(a, b)` serves, so it was 84 MB of pure duplication. The same mistake appears on the AUS bridge (29 MB) and the denial bridge (12 MB).

Proof rather than assertion. Drop all three, then run the lookup they were supposedly for:

```sql
SELECT count(*) FROM marts.br_application_race
WHERE activity_year = 2024 AND application_sk BETWEEN 1000000 AND 1000500;
```

| | plan | warm time |
|---|---|---|
| with `idx_br_race_app` | Index Only Scan using `idx_br_race_app` | 1.27 ms |
| after dropping it | Index Only Scan using `br_application_race_pkey` | **0.12 ms** |

Identical plan shape, and the database went from 2,524 MB to 2,399 MB. **125 MB recovered for no loss at all**, on a model where the entire `marts` schema is 1.7 GB.

`idx_br_race_code` stays, because `race_code` appears in no primary key and the phase 08 race analysis filters on it. The three prefixes are removed from `005_constraints_indexes.sql`, with the reason written in the file so nobody adds them back.

**Why this happened.** I created one index per join path without checking whether the primary key already covered it. It is the most common index mistake there is, and the thing that caught it was reading `pg_stat_user_indexes` sorted by size, which takes ten seconds and should be a habit.

Note also that every `idx_scan` in that table is zero. The bridges are used by aggregate queries that read all of their rows, and a sequential scan is correct for those. An index with zero scans is not automatically wrong, since three of these are primary keys enforcing uniqueness, but an index with zero scans that is not enforcing anything is exactly what section 5 is about.

---

## 6. Raising `work_mem` fixed the spill and did not fix the query

The duplicate detection query from phase 06 aggregates 1.75 million 32 character hashes, which at `work_mem = 4MB` cannot be done in memory.

```sql
SELECT row_hash, count(*) FROM marts.fct_application GROUP BY 1 HAVING count(*) > 1;
```

| `work_mem` | batches | disk usage | time |
|---|---|---|---|
| 4 MB | 161 | 95,984 kB | 1,512 ms |
| 256 MB | 1 | none | 1,458 ms |

96 MB of temporary files, 161 hash batches, completely eliminated, for a **3.6 percent improvement**. Which is the opposite of what the conventional advice predicts.

The explanation is that the spill was never the bottleneck. 96 MB of temporary files on a machine with free page cache is almost free, and the actual work is hashing and comparing 1.75 million 32 byte strings, which costs the same either way. The `Disk Usage` line looks alarming and was not the problem.

Two things follow. `work_mem` is worth raising for sorts and hash joins that spill *large* amounts relative to available memory, and is not a general speed dial. And 270 MB of `work_mem` per query node, on a server with 128 MB of `shared_buffers`, is a configuration that would fall over under concurrency, which makes this a bad trade even at 3.6 percent.

This is also the second place the 32 character key costs something, which leads to the last measurement.

---

## 7. The price of the reproducible key, measured

The deterministic key from phase 06 is `md5(row)`, stored as `char(32)`. Its unique index is the largest object on every partition:

| index on the 2024 partition | size |
|---|---|
| `activity_year_row_hash_dup_seq_key` | 25 MB |
| `pkey` | 12 MB |
| `lei_census_tract_idx` | 11 MB |
| the other four combined | about 9 MB |

Phase 05 guessed that hashing to a `bigint` would cut this "by about three quarters". That guess was wrong, and the measurement took one minute:

```sql
CREATE INDEX tmp_hash64 ON marts.fct_application_2024
  ((('x' || substr(row_hash,1,16))::bit(64)::bigint), dup_seq);
-- 12 MB
```

**12 MB against 25 MB, a 52 percent saving, not 75 percent.** Across four partitions that is 52 MB rather than the 85 MB implied by the guess. Still worth having, and now a number rather than an intuition.

It is not adopted, for a stated reason. Truncating md5 to 64 bits gives roughly a 1 in 10^10 chance of a collision across 1.75 million rows, which is small but not zero, and a collision would silently merge two applications into one key. The 13 MB per partition buys certainty on the property this whole design exists for, which is that a rebuild anywhere produces identical keys. If the model grew to 50 million rows the trade would change and the calculation should be redone.

---

## 8. What actually mattered, in order

| change | effect | cost |
|---|---|---|
| Partition by year | 5.6x on year-filtered queries, a quarter of the buffers | none, it is the model's grain |
| Add `action_taken` to `idx_fct_decided` | 2.3x on the dominant aggregate, 3x fewer buffers | 96 kB per partition |
| `(lei, census_tract)` index | 5.1x and 46x fewer buffers on lender queries | 11 MB per partition |
| Drop three redundant prefix indexes | 125 MB recovered, no plan change | none |
| `FILTER` aggregates over correlated subqueries | see below | none, it is how the query is written |
| Raise `work_mem` to 256 MB | 3.6 percent, and a fragile configuration | 270 MB per node |
| Hash key to `bigint` | 52 MB across the model | a non-zero collision risk, so not adopted |

On the fifth row: the within-tract comparison in phase 08 section 7, written with a correlated subquery per tract, takes 762 ms for **200 tracts and one group**. Written as `FILTER` aggregates in a single pass it takes 522 ms for **all 5,184 tracts, both groups and all four years**. Extrapolating the correlated version to the same work is about 40 seconds against 0.5, roughly 75 times, and it is a property of how the query is written rather than anything the database can be configured to fix.

That ordering is the actual conclusion of this phase. The two largest wins came from the data model and from one column in an index. The configuration change that tuning advice usually leads with came seventh.

---

## 9. What is worth defending in a review

| choice | the alternative | why this one |
|---|---|---|
| Report warm timings after three runs | first run | the cold run reversed a conclusion twice in this project |
| Report buffers next to time | time alone | buffers do not depend on what else the machine is doing |
| Force baselines with `enable_indexscan = off` | drop and recreate the index | same comparison, no rebuild, no risk to the model |
| `action_taken` in the key, not just the predicate | partial index alone | the predicate cannot supply a value to a `FILTER` |
| Keep the `char(32)` key index | truncate to `bigint` and save 52 MB | a 1 in 10^10 collision would silently merge two applications |
| Delete the three prefix indexes | keep them in case | the primary key gives the identical plan, 125 MB cheaper |
| Modest server configuration | tune the server until it is fast | a result on a box with more RAM than data proves nothing |
| Leaving both mistakes in the document | fixing them quietly | the fix is worth less than the reason it was needed |
