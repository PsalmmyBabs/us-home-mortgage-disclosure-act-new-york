# Mortgage lending in New York, 2022 to 2025

A PostgreSQL analytics project on 1,755,419 real mortgage applications, built from published regulatory data and **runnable in your browser without installing anything**.

### ▶ [Open the playground](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/) · [Browse the data dictionary](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/catalog/) · [See the ERD](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/erd/) · [Project home](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/)

The playground gives you fifteen tables, a SQL box and the twenty-two queries below, running in your browser. Nothing is installed, no account is created, and no data leaves your machine.

---

## Two questions

**What does this market look like?** What was borrowed, by whom, where, on what terms, at what price, and why applications failed. That is [phase 08](docs/08_analysis.md).

**And does the answer differ by applicant group** once income, product, neighbourhood and lender are held constant? That is [phase 08b](docs/08b_analysis_disparity.md).

They are separate documents on purpose. A single document that answers both answers neither well.

---

## What the market looks like

| | |
|---|---|
| Applications, purchased loans excluded | **1,596,676** |
| Approved | 996,548, a 62.4% approval rate |
| Disbursed | **371.42bn** |
| Share of applications that are 30-year | **67.5%**, and 78% of the money |
| Share that are conventional | 89.9% |
| Largest single reason for denial | **debt-to-income, 36.7%** of denials |
| New York City's share | 30% of applications, **50% of the dollars**, lowest approval rate in the state |
| Median approved loan, 2025 | 255,000, against a **mean of 401,264** |
| Median rate on a new loan | 4.375% in 2022, **6.875% in 2024** |

**Approval fell 2.8 points in 2023 and never came back.** Volume has recovered to 79 percent of 2022 and dollars to 73 percent, but the willingness to say yes has sat within 0.3 points of its new, lower level for three years.

## What the data says about who gets credit

| finding | figure |
|---|---|
| Denial rate spread between lenders **in the same census tract** | **30.6 points** median, 97.3 at the extreme |
| Applications ending in "file closed for incompleteness", by lender | 0.2% to 28.5%, **a factor of 142** |
| White against all other reported races combined, 2025 | 22.4% against 30.7% denied |
| Black denial rate against White, 2025 | 39.6% against 22.4% |
| The same gap for applicants earning over 200k | 30.2% against 15.7% |
| Census tracts with 100+ decided applications from both groups | 62, and the Black rate is higher in **60** |
| Share of the 2023 tightening that was products denying more, not the product mix changing | **76%** |
| Rate spread paid by approved Black borrowers, against White | 1.8 times, on both mean and median |

**The finding with the clearest action is not the one you would expect.** Which lender an applicant approaches matters more than anything else measured here. Two lenders in the same census tract, each deciding at least thirty applications, typically differ by 30.6 percentage points in how often they say no. That dwarfs every group gap in the project.

**None of this is causal.** HMDA does not contain a credit score, so the honest claim is narrower and still substantial: the disparity is not explained by income, product, neighbourhood or lender choice, because it persists after holding each of those constant. Whether it is explained by creditworthiness cannot be tested with this data.

---

## The twenty-two questions, and the SQL that answers them

**Click a query number and the playground opens with that query loaded and already executed**, against the real 1.75 million rows, in your browser. You can then edit it and press Ctrl + Enter to try your own version.

### The market

| | the question | what the query returns |
|---|---|---|
| [01](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=01) | How did the market move between 2022 and 2025? | Applications fell 31% in a year and dollars 43%. Volume is back to 79% of 2022, but the approval rate dropped 2.8 points and stayed down. |
| [02](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=02) | Which loan types carry this market? | 89.9% conventional. Conventional and FHA together are 97.7% of applications and sit 2.6 points apart on approval. |
| [03](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=03) | What are people borrowing for? | Home purchase is 46% of applications and 65% of the money. Home improvement is 15.5% of applications and 4.3% of the money. |
| [04](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=04) | Where does the loan sit in the capital stack? | A quarter is subordinate-lien, approved 12.6 points less often for a median loan a third the size. |
| [05](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=05) | How long do these loans run? | 67.5% are 30 years or longer, and they are 78% of the money. The 15 to 30 year bands approve worst, because that is where second-lien lending sits. |
| [06](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=06) | How big are the loans really? | The mean sits above the 60th percentile every year. In 2025 the mean is 401,264 and the median 255,000. |
| [07](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=07) | Does age change the outcome? | Approval falls 12.7 points from 25-34 to 65-and-above, and the median loan falls from 295,000 to 155,000. The "age not provided" band turns out to be 84% companies. |
| [08](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=08) | Who applies, by sex and race? | A jointly named application is approved about 8 points more often than a single applicant of the same race, in every group. |
| [09](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=09) | Where does the lending happen? | New York City is 30% of applications, 50% of the dollars, and the lowest approval rate. Ranking by volume and by dollars gives different lists. |
| [10](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=10) | How does income translate into loan size? | The level rises and the multiple falls: 2.62 times income under 50k, 1.53 times over 200k. Approval stops improving above 150k. |
| [11](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=11) | What does borrowing cost? | Within 2025, purpose spans 51 basis points and the lowest income band pays 37.5 more than the highest. Across years the environment moved 250. |
| [12](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=12) | Why do applications fail? | Debt-to-income is 36.7% of denials, nearly as much as credit history and collateral combined. |

### Who gets credit

| | the question | what the query returns |
|---|---|---|
| [13](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=13) | Did credit get harder to obtain? | Denial rose from 23.3% in 2022 to 26.9% in 2023, easing to 24.9% by 2025. |
| [14](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=14) | Why does the denominator matter? | Only 54.2% of rows are originated and 18.2% denied. Every rate in the disparity analysis uses decided applications only. |
| [15](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=15) | Do outcomes differ by group? | 2025: 22.4% for White against 30.7% for all other reported races combined, and 39.6% for Black applicants. |
| [16](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=16) | Does the gap survive income? | No. It is 4.5 to 15.1 points in every band against the combined group, and 13.6 to 19.3 against Black applicants specifically. |
| [17](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=17) | Was the 2023 tightening mix or behaviour? | A shift share splits the 3.65 point rise into 0.86 from mix and 2.79 from products denying more. **I predicted the opposite.** |
| [18](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=18) | Does it survive the neighbourhood? | In the 62 tracts with 100+ decided applications from both groups, the Black rate is higher in 60, by a median of 10.9 points. |
| [19](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=19) | How much does the lender matter? | In 532 tracts with four or more active lenders, the median gap between strictest and loosest **in the same tract** is 30.6 points. |
| [20](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=20) | How many applicants report more than one race? | 18,051, not 106,971. HMDA race codes are hierarchical and counting them naively overstates it sixfold. |
| [21](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=21) | Is denial the only way an application ends badly? | No. "File closed for incompleteness" ranges from 0.2% to 28.5% between large lenders. |
| [22](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=22) | Can every published row be accounted for? | 1,754,846 modelled plus 573 quarantined equals 1,755,419 published. Nothing was silently dropped. |

The SQL lives in [`playground/queries/`](playground/queries) and runs unchanged against both PostgreSQL and the browser build. A [parity test](playground/parity_test.py) executes all twenty-two against both engines, plus the three labelled views, and fails on any difference.

---

## The data model

Fifteen tables: one partitioned fact, eight dimensions, four bridges, a quarantine table and a code reference.

**[Open the entity relationship diagram](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/erd/)** for the keys and the joins, drawn from the foreign keys as they exist in the database. **[Open the data dictionary](https://psalmmybabs.github.io/us-home-mortgage-disclosure-act-new-york/catalog/)** for every column, type, index and constraint, generated from `pg_catalog` at build time.

Three design decisions are worth knowing before you read a query:

**Most keys carry `activity_year`.** A lender's asset size, a tract's median income and an MSA's name all change between years, so a key of `lei` alone would silently mix vintages.

**Four relationships are bridges, not columns.** HMDA lets a filer record up to five races and five ethnicities for each of two parties, four denial reasons and several underwriting systems. Flattening those into the fact table would break first normal form, and it is what makes query 20 go wrong if you are not careful.

**The fact table has no natural key.** The Bureau strips every loan identifier before publication, so the business key is `md5` of the source row plus an occurrence number. That makes it reproducible: the model was built independently on a Linux container and a Windows laptop and the denial rates match to one decimal place.

---

## Where the data comes from

| | |
|---|---|
| Loan Application Register, Transmittal Sheet, MSA/MD descriptions | [CFPB HMDA Data Browser](https://ffiec.cfpb.gov/data-browser/) |
| Institution hierarchy, asset size, CRA rating, minority-owned flag | [Philadelphia Fed HMDA Lender File](https://www.philadelphiafed.org/surveys-and-data/consumer-finance-data/home-mortgage-disclosure-act-lender-file) |
| The exact files and vintages used | [`RUNBOOK.md`](RUNBOOK.md) |
| The Parquet the playground reads | [`docs/playground/data/`](docs/playground/data) |

The loan registers are 638 MB of CSV and are not committed. The Parquet export that powers the playground is, at 82 MB across nineteen files, one per table and one per year of the fact table.

The published register is modified by the Bureau to protect applicant privacy. This project makes no attempt at re-identification and does not combine these files with any other source for that purpose. United States federal government works, no copyright under 17 U.S.C. 105.

---

## How the numbers are checked

```sql
SELECT * FROM marts.assert_results ORDER BY severity, assertion;
```

Eight assertions, split into `build_error`, which must be zero, and `source_defect`, which is a real problem in the filed data carrying a documented tolerance so that the build is not permanently red over something outside its control. One command gates a merge:

```bash
test "$(psql -tAqc 'SELECT count(*) FROM marts.assert_failures' hmda)" = "0"
```

Nothing is deleted. Impossible values are quarantined with the rule they broke. Missing values keep the *reason* they are missing, because "denied so there is no interest rate" and "withheld by an exempt filer" are different facts. Byte-identical duplicate rows are numbered rather than deduplicated, because which reading is true cannot be determined from the data.

---

<details>
<summary><b>How it was built, in eleven phases</b> (click to expand)</summary>

<br>

Each phase ends with a table headed *what is worth defending in a review*, and each one shows at least one thing that went wrong.

| | what it covers | the part worth reading |
|---|---|---|
| [01](docs/01_sourcing_and_provenance.md) | Sourcing and provenance | Publication vintages, and why mixing them changes the numbers |
| [02](docs/02_profiling_the_raw_data.md) | Profiling the raw data | Benford's law, and 80,167 rows carrying a code the regulator documents nowhere |
| [03](docs/03_landing_the_raw_layer.md) | Landing the raw layer | Why the raw layer is all `text` and is never edited |
| [04](docs/04_data_model.md) | Designing the data model | The four splitting rules, with measurements behind each one |
| [05](docs/05_building_the_objects.md) | Building the objects | Partitioning, constraints after the load, and the honest cost of a reproducible key |
| [06](docs/06_transforming_raw_into_the_model.md) | Transforming raw into the model | The five things that happen to a bad record, and the trap behind query 20 |
| [07](docs/07_quality_assertions.md) | Quality assertions | Build errors against source defects, and a gap found while writing the document |
| [08](docs/08_analysis.md) | The analysis | What this market is, in twelve findings |
| [08b](docs/08b_analysis_disparity.md) | The disparity analysis | Nine findings, including one where my prediction was backwards |
| [09](docs/09_performance_tuning.md) | Performance tuning | An index the planner ignored, and 125 MB of indexes that should never have existed |
| [10](docs/10_playground.md) | The browser playground | Four silent differences between PostgreSQL and DuckDB, each found by a test rather than a user |

**Documentation that cannot go stale.** `migrations/009_comments.sql` puts the description of every table and all 175 table columns into the PostgreSQL catalogue itself, and `catalog/build_catalog.py` generates the published dictionary from `pg_catalog` at build time. `playground/sync_views.py` does the same job for the browser build, writing the view definitions in `bootstrap.sql` from `pg_get_viewdef` rather than leaving them hand-written, because the hand-written ones had drifted.

**Repository layout.**

```
migrations/       000 to 009, run in order, about eight minutes end to end
seed/             the loader scripts and one small derived CSV
playground/       the source that builds the browser site
playground/queries/  the twenty-two published queries
catalog/          the source that builds the data dictionary
docs/             the eleven phase documents
docs/playground/  the published playground
docs/catalog/     the published data dictionary
docs/erd/         the published entity relationship diagram
RUNBOOK.md        exact source files, vintages and download links
SETUP_WINDOWS.md  building the database from nothing on Windows
```

**Rebuild it yourself.** [`RUNBOOK.md`](RUNBOOK.md) names the exact datasets and vintages, [`SETUP_WINDOWS.md`](SETUP_WINDOWS.md) is the step by step build, and [`docs/DEPLOY_PLAYGROUND.md`](docs/DEPLOY_PLAYGROUND.md) rebuilds and republishes the browser version.

</details>

---

## Three things this repository does differently

**It shows the mistakes.** Phase 08b keeps a prediction of mine that the measurement contradicted. Phase 09 shows an index I built being ignored by the query planner, and 125 MB of indexes that duplicated a primary key. Phase 10 lists four cases where PostgreSQL and DuckDB silently returned different answers. Phase 07 documents an assertion gap found while writing the document rather than patching it quietly. A build that never admits to a gap is not a build anyone should trust.

**The claims are executable.** Every figure above is one click from the query that produced it, running against the real data rather than a screenshot. If you think a number is wrong, you can check it in about ten seconds.

**The keys are reproducible.** Rebuild the whole model on a different machine and you get the same surrogate keys, because they are derived from the source rows rather than from an identity column.

---

## Author

**Samuel Babajide** — Data Scientist specialising in applied analytics and predictive modelling within complex, regulated environments.

[LinkedIn](https://linkedin.com/in/samuelbbabajide) · [GitHub](https://github.com/PsalmmyBabs) Questions and corrections are welcome in the issues.
