# Phase 01: Sourcing and provenance

What data this project uses, where it came from, why these boundaries were drawn, and what may and may not be republished.

Next phase: [02 Profiling the raw data](02_profiling_the_raw_data.md)

---

## 1. The question this data has to answer

> Who gets access to mortgage credit in New York, on what terms, and does the answer differ by applicant group once income, product and lender are held constant?

That question set the sourcing requirements. It needs applicant demographics, a decision outcome, geography fine enough to hold a neighbourhood constant, and more than one lender so a lender can be compared against its peers. Those four requirements ruled out most public financial data before a single file was downloaded.

## 2. The five sources

| # | source | publisher | what it provides |
|---|---|---|---|
| 1 | Loan Application Register (LAR) | CFPB / FFIEC | one row per mortgage application: outcome, demographics, geography, money, terms |
| 2 | Transmittal Sheet | CFPB / FFIEC | the name, city, state and agency of every filing institution |
| 3 | MSA/MD Description | CFPB / FFIEC | metropolitan area names |
| 4 | Census tract attributes | FFIEC, pre-merged into the LAR | tract population, minority share, income relative to its metro |
| 5 | HMDA Lender File ("Avery file") | Federal Reserve Bank of Philadelphia | parent organisation, top holder, asset size, CRA exam rating, minority-owned flag |

Sources 1 to 4 come from `ffiec.cfpb.gov`. Source 5 comes from `philadelphiafed.org`.

**Source 5 replaced something that no longer exists.** The CFPB used to publish a Reporter Panel carrying institution hierarchy. It has been retired, and the CFPB's own publication page now directs users to the Philadelphia Fed file instead. The replacement is better than what it replaced: it adds asset size, which allows a lender to be compared with genuine peers rather than the whole market, and a CRA exam rating, which is an independent regulatory assessment to set beside any disparity this project measures.

## 3. The four boundaries, and why each was drawn there

### Geography: New York State, every lender

The HMDA Data Browser exports filtered by state with no lender filter.

An earlier pull was filtered to a single LEI and was **rejected**. One lender gives 24,722 applications and no way to ask the question that matters in fair lending, which is whether a given lender denies more often than its peers operating in the same neighbourhoods. Taking every lender in one state instead of a hand-picked set of lenders also removes any argument about selection: the universe is complete by definition.

Result: **756 to 802 lenders per year**, across 63 counties, 15 metropolitan areas and roughly 5,200 census tracts.

### Years: 2022, 2023 and 2024 as the main series, 2025 as an appendix

The four-year window spans a real interest rate cycle, so there is genuine market movement to explain rather than three flat years.

2025 is held out of the main series for a documented reason given in section 4.

### Scale: about 1.75 million applications

National files run to several gigabytes and would add nothing this question needs. One state for four years gives 1,755,419 applications, which is large enough that an index visibly changes a query plan and small enough to rebuild in eight minutes on a laptop.

### Subject: applications, not loan performance

HMDA records what lenders decided, not what borrowers subsequently paid. This project therefore cannot say anything about arrears, default, roll rates or vintage curves, and does not try. That limitation is stated here so it is not mistaken for an oversight later.

## 4. Publication vintage, which changes the numbers

The CFPB publishes each filing year three times as late and resubmitted filings accumulate. The Data Browser serves the most complete version available for each year, so **a four-year comparison mixes vintages**.

| filing year | dataset served | freeze date | completeness |
|---|---|---|---|
| 2022 | Three Year National Loan-Level | 31 Dec 2025 | 34 months of resubmissions |
| 2023 | One Year National Loan-Level | 19 May 2025 | 12 months of resubmissions |
| 2024 | One Year National Loan-Level | 2 Jun 2026 | 12 months of resubmissions |
| 2025 | Snapshot National Loan-Level | 2 Jun 2026 | provisional, one month after the filing deadline |

The gap between Three Year and One Year is small, typically a fraction of a percent. The gap between either and a Snapshot is not, which is why **2025 is reported separately as "latest available, provisional" and excluded from the trend series**.

This is recorded in the database rather than in a comment, so any query can carry its own provenance:

```sql
SELECT * FROM ref.ref_source_vintage;
SELECT activity_year, source_dataset, source_freeze_date, is_provisional FROM marts.dim_date;
```

Two consequences to keep in mind. Some of any apparent year-on-year movement is filing completeness rather than market behaviour. And re-running this project in a year's time will produce slightly different 2024 and 2025 figures, because those years will have matured into more complete vintages.

## 5. Licence and what may be republished

**The HMDA files are United States federal government works.** Under 17 U.S.C. 105 federal works carry no copyright in the United States, and the CFPB publishes this data explicitly for public use. There is no licence to accept and no restriction on republication. This is not legal advice, but as public data goes the position is about as clean as it gets.

**The real obligation is not copyright, it is re-identification.** The Bureau describes the published register as "modified by the Bureau to protect applicant and borrower privacy". Loan identifiers are stripped and some values are coarsened. The commitment this project makes is therefore not to attempt re-identification of any applicant, and not to combine this file with other sources for that purpose.

**The Philadelphia Fed file asks for attribution**, which is given: Federal Reserve Bank of Philadelphia, HMDA Lender File (Avery File).

**What this repository does and does not contain.** The loan registers are 638 MB across four years and are not committed. The repository holds the code to build the database, a runbook naming the exact files and vintages, and one small derived CSV: the lender file converted from the publisher's spreadsheet and filtered to these four years, committed so that building the database requires nothing but PostgreSQL. Anyone can reproduce the database from the published sources, and that reproduction has been verified on two independent machines producing identical figures.

## 6. What was rejected, and why

Recording the rejections matters as much as recording the choice, because it shows the boundaries were drawn rather than inherited.

| candidate | why not |
|---|---|
| Single-lender LAR export | no peer comparison possible, and 24,722 rows is too small for meaningful query tuning |
| National LAR | gigabytes, and adds nothing the question needs |
| 2020 to 2022 window | fully consistent vintages, but dominated by the pandemic refinancing boom and four years stale |
| Fannie Mae / Freddie Mac loan performance | has the repayment outcomes HMDA lacks, but requires registration and cannot be redistributed |
| Lending Club | 2.2 million real loans in a single flat table, so no joins, which defeats the purpose |
| UK datasets | no public row-level UK consumer credit data exists; UK GDPR and FCA rules mean bureau and lender data is never published at row level |

**On that last point.** The question this project asks is not a US-only question. The FCA's Financial Lives 2024 survey found 4.6 million UK adults declined a financial product in the previous two years, 22 percent of regulated credit applicants declined, and Black adults declined at 20 percent against an 8 percent average. The UK has the problem and does not publish the data. HMDA is the market where the data exists, which is itself worth stating.
