# Phase 08: The analysis

Nine findings, each one a query against the model built in phases 04 to 07, and each one stated inside the limits set out in phase 02.

Previous phase: [07 Quality assertions](07_quality_assertions.md) · Next phase: [09 Performance tuning](09_performance_tuning.md)

---

## 1. The denominator decision, which comes before every number

HMDA records eight possible outcomes for an application, and only two of them are a lender's credit decision:

| code | outcome | rows | share of all 1,754,846 |
|---|---|---|---|
| 1 | Loan originated | 951,371 | 54.2% |
| 3 | Application denied | 319,473 | 18.2% |
| 4 | Withdrawn by applicant | 193,863 | 11.0% |
| 6 | Purchased loan | 158,170 | 9.0% |
| 5 | File closed for incompleteness | 78,521 | 4.5% |
| 2 | Approved but not accepted | 45,177 | 2.6% |
| 8 | Preapproval approved, not accepted | 6,982 | 0.4% |
| 7 | Preapproval request denied | 1,289 | 0.1% |

A denial rate is therefore `denied / (originated + denied)`, and nothing else. Measured over all 1,754,846 rows the denied share is 18.2 percent. Measured correctly, over decided applications only, it is 25.1 percent. Those are the same data and a 7 point difference, because a purchased loan is a loan someone else already approved and a withdrawal is the applicant's decision rather than the lender's.

This is why the model puts the definition in one place rather than in every query:

```sql
(f.action_taken IN ('1','3')) AS is_decided,
(f.action_taken = '3')        AS is_denied
```

Every figure below uses `is_decided` as the denominator. Getting this wrong is the single most common way to publish a wrong fair-lending number, and the reason phase 05 built a partial index on exactly this predicate.

---

## 2. Finding 1: the market tightened, then partly recovered

```sql
SELECT activity_year,
       count(*) AS decided,
       round(100.0*count(*) FILTER (WHERE action_taken='3')/count(*), 2) AS denial_pct
FROM marts.fct_application
WHERE action_taken IN ('1','3')
GROUP BY 1 ORDER BY 1;
```

| year | decided applications | denial rate |
|---|---|---|
| 2022 | 400,563 | 23.29% |
| 2023 | 277,970 | 26.94% |
| 2024 | 283,192 | 26.26% |
| 2025 | 309,119 | 24.87% |

Decided volume falls by 31 percent from 2022 to 2023 as rates rise, and the denial rate moves 3.65 points the other way. 2025 is the provisional vintage, so it is shown but not used for any trend claim. Phase 01 section 4 explains why.

---

## 3. Finding 2: what caused the 2023 deterioration, and where I was wrong

**I predicted this incorrectly before measuring it, and the correction is more instructive than the result.**

My reasoning was that the 2023 collapse in refinancing would push the aggregate denial rate *down*, because refinancing carries a higher denial rate than home purchase and there was suddenly much less of it. That is sound as far as it goes, and it is wrong, because it only considered the mix and ignored what happened inside each product.

A shift-share decomposition separates the two. The change in an aggregate rate is the sum of a **mix effect** (the same products, in different proportions) and a **within effect** (the same proportions, at different rates).

```sql
WITH y AS (
  SELECT f.activity_year AS yr, p.loan_purpose,
         count(*) FILTER (WHERE f.action_taken IN ('1','3')) AS dec,
         count(*) FILTER (WHERE f.action_taken = '3')        AS den
  FROM marts.fct_application f
  JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
  WHERE f.activity_year IN (2022, 2023)
  GROUP BY 1,2),
t AS (SELECT yr, sum(dec) AS tot FROM y GROUP BY 1),
j AS (SELECT y.loan_purpose,
        max(CASE WHEN yr=2022 THEN 1.0*y.dec/t.tot END) AS w22,
        max(CASE WHEN yr=2023 THEN 1.0*y.dec/t.tot END) AS w23,
        max(CASE WHEN yr=2022 THEN 1.0*y.den/y.dec END) AS r22,
        max(CASE WHEN yr=2023 THEN 1.0*y.den/y.dec END) AS r23
      FROM y JOIN t USING (yr) GROUP BY 1)
SELECT round(100*sum((w23-w22)*r22), 3) AS mix_effect,
       round(100*sum(w23*(r23-r22)), 3) AS within_effect
FROM j;
```

| effect | points | share of the change |
|---|---|---|
| mix, products changing weight | +0.860 | 23.6% |
| within, products denying more | +2.790 | **76.4%** |
| total | +3.650 | matches 23.29 to 26.94 |

So the answer is the opposite of my prediction. Refinancing shrinking did push the rate down, by 1.09 points for refinancing and 1.38 for cash-out. But home improvement and "other purpose" grew from 25.0 to 32.1 percent of the market combined, and both deny at over 40 percent, which more than cancelled it out. And underneath all of that, **every single product denied more often in 2023 than in 2022.**

| purpose | share 2022 | share 2023 | rate 2022 | rate 2023 | mix | within |
|---|---|---|---|---|---|---|
| Home improvement | 14.9% | 18.2% | 40.9% | 44.5% | +1.361 | +0.657 |
| Other purpose | 10.1% | 13.9% | 41.8% | 46.3% | +1.579 | +0.628 |
| Refinancing | 13.8% | 9.1% | 23.1% | 28.9% | -1.087 | +0.528 |
| Home purchase | 44.8% | 47.9% | 12.6% | 13.7% | +0.390 | +0.502 |
| Cash-out refinancing | 16.4% | 10.9% | 25.2% | 29.5% | -1.383 | +0.469 |

The lesson is the one worth keeping: an aggregate can move for two completely different reasons, and a plausible story about one of them is not an answer. The decomposition is four lines of arithmetic and it is the difference between being confidently wrong and being right.

---

## 4. Finding 3: outcomes differ sharply by applicant group

```sql
SELECT a.derived_race,
       count(*) AS decided,
       round(100.0*count(*) FILTER (WHERE f.action_taken='3')/count(*), 1) AS denial_pct
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken IN ('1','3') AND f.activity_year = 2025
GROUP BY 1 ORDER BY 2 DESC;
```

| group (2025) | decided | denial rate |
|---|---|---|
| Joint | 5,410 | 18.3% |
| White | 197,892 | 22.4% |
| Asian | 27,956 | 24.5% |
| Race not available | 52,526 | 27.8% |
| **Black or African American** | 22,523 | **39.6%** |
| American Indian or Alaska Native | 1,308 | 45.0% |
| Native Hawaiian or Other Pacific Islander | 583 | 49.9% |

A 17.2 point gap between the two largest groups. That number on its own is close to meaningless, because applicants differ in income, in what they are borrowing for, in where the property is and in which lender they approached. The rest of this phase is about removing those explanations one at a time.

---

## 5. Finding 4: the gap survives income

```sql
CASE WHEN income_thousands < 50 THEN '1. under 50k'
     WHEN income_thousands < 100 THEN '2. 50-100k' ... END AS band
```

| applicant income (2025) | Black denial | White denial | gap |
|---|---|---|---|
| under 50k | 59.2% | 45.3% | 13.9 |
| 50k to 100k | 44.9% | 25.6% | 19.3 |
| 100k to 150k | 35.6% | 19.2% | 16.4 |
| 150k to 200k | 29.8% | 16.2% | 13.6 |
| 200k and above | 30.2% | 15.7% | 14.5 |

Income explains a great deal about denial in general: the rate halves from the bottom band to the top. It explains very little about the gap, which is between 13.6 and 19.3 points in every band. A Black applicant earning over 200,000 dollars is denied at 30.2 percent, which is higher than a White applicant earning between 50,000 and 100,000.

## 6. Finding 5: it survives the product

| loan purpose | overall | Black | White |
|---|---|---|---|
| Home purchase | 13.3% | 20.8% | 11.6% |
| Cash-out refinancing | 27.0% | 39.0% | 23.9% |
| Refinancing | 26.4% | 40.5% | 24.3% |
| Home improvement | 41.5% | **64.5%** | 34.7% |
| Other purpose | 44.1% | 62.4% | 38.5% |

Home improvement is the finding inside the finding. It is the second largest product in this market at 209,703 decided applications, it denies at 41.5 percent overall, and for Black applicants it denies at 64.5 percent. These are loans secured on a property the applicant already owns, to maintain or improve it.

## 7. Finding 6: it survives geography, measured two ways

First, denial rises with the minority share of the neighbourhood:

| tract minority population | decided | denial rate |
|---|---|---|
| under 20% | 517,898 | 21.7% |
| 20 to 40% | 373,937 | 23.6% |
| 40 to 60% | 139,453 | 26.2% |
| 60 to 80% | 90,730 | 28.9% |
| 80% and above | 141,904 | 37.2% |

That gradient is consistent with either explanation, because applicants are not randomly distributed across tracts. So the stronger test is to compare applicants **within the same census tract**, which holds the neighbourhood, the local housing market and the local economy constant by construction.

```sql
WITH t AS (
  SELECT f.census_tract,
    100.0*count(*) FILTER (WHERE f.action_taken='3' AND a.derived_race='Black or African American')
      / nullif(count(*) FILTER (WHERE a.derived_race='Black or African American'),0) AS rb,
    100.0*count(*) FILTER (WHERE f.action_taken='3' AND a.derived_race='White')
      / nullif(count(*) FILTER (WHERE a.derived_race='White'),0) AS rw
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3') AND f.census_tract <> 'UNKNOWN'
    AND a.derived_race IN ('White','Black or African American')
  GROUP BY 1
  HAVING count(*) FILTER (WHERE a.derived_race='Black or African American') >= 100
     AND count(*) FILTER (WHERE a.derived_race='White') >= 100)
SELECT count(*) AS tracts,
       count(*) FILTER (WHERE rb > rw) AS black_rate_higher,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY rb-rw)::numeric, 1) AS median_gap
FROM t;
```

62 tracts have at least 100 decided applications from each group. The Black denial rate is higher in **60 of the 62**, the median gap is 10.9 points, and the range runs from -2.6 to +23.8. Two tracts out of 62 going the other way is about what random variation would produce.

## 8. Finding 7: it survives the lender

| lender | decided | Black denial | White denial |
|---|---|---|---|
| ROCKET MORTGAGE | 65,757 | 30.9% | 22.1% |
| CBNA Year to Date | 54,894 | 57.9% | 38.1% |
| United Wholesale Mortgage | 48,703 | 20.6% | 12.2% |
| M&T BANK | 44,764 | 49.1% | 29.4% |
| JPMorgan Chase Bank, NA | 43,981 | 20.9% | 12.8% |
| Bank of America NA | 37,058 | 65.3% | 46.2% |

Six of the largest lenders in the market, every one of them denying Black applicants more often than White applicants, with gaps between 8.1 and 19.8 points. The ratio is strikingly consistent: each lender's Black denial rate is between 1.40 and 1.69 times its White rate, whatever its overall level. Whatever is producing the pattern is not one outlier institution.

---

## 9. Finding 8: lenders differ from each other more than they differ from their own average

This one reframes everything above, and it is the most useful finding in the project for anyone who has to act.

```sql
WITH lt AS (
  SELECT census_tract, lei, count(*) AS dec,
         100.0*count(*) FILTER (WHERE action_taken='3')/count(*) AS rate
  FROM marts.fct_application
  WHERE action_taken IN ('1','3') AND census_tract <> 'UNKNOWN'
  GROUP BY 1,2 HAVING count(*) >= 30)
SELECT count(*) AS tracts,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY spread)::numeric,1) AS median_spread
FROM (SELECT census_tract, max(rate)-min(rate) AS spread
      FROM lt GROUP BY 1 HAVING count(*) >= 4) s;
```

In the 532 census tracts where at least four lenders each made at least 30 decisions:

| | denial rate spread between lenders in the same tract |
|---|---|
| 25th percentile | 22.8 points |
| **median** | **30.6 points** |
| 75th percentile | 39.5 points |
| maximum | 97.3 points |

In a typical New York census tract, the most and least restrictive active lender are 30 points apart on the same neighbourhood. That dwarfs the 17.2 point headline racial gap and the 3.65 point four-year market movement.

It is also the finding with a direct implication, because it is the one an individual can act on: which lender an applicant approaches matters more than almost anything else measured here. And for a regulator it identifies exactly where to look, since "this lender is 30 points above its peers in the same tracts" is a specific, testable, peer-controlled claim rather than a market-wide average.

---

## 10. Finding 9: denial is not the only channel

4.47 percent of all applications, 78,521 of them, end in "file closed for incompleteness" rather than a decision. That is not a denial, so it is invisible to every number in this document.

| lender (20,000+ applications) | closed for incompleteness |
|---|---|
| DISCOVER BANK | 28.5% |
| Bank of America NA | 11.2% |
| NEWREZ LLC | 9.3% |
| TD Bank | 7.3% |
| ... | ... |
| M&T BANK | 1.1% |
| Premium Mortgage Corporation | 0.8% |
| ROCKET MORTGAGE | 0.2% |

**0.2 percent to 28.5 percent, a factor of 142.** Two lenders in the same state, in the same years, under the same rules, differ this much in how often an application simply stops. Whatever that measures, it is not applicant behaviour, because applicant behaviour does not vary by a factor of 142 between two national banks.

And the channel is not neutral across groups:

| group | closed for incompleteness | withdrawn by applicant |
|---|---|---|
| White | 4.3% | 10.7% |
| Black or African American | 5.6% | 13.2% |
| Asian | 5.7% | 13.1% |

A fair-lending review that looks only at denial rates misses this entirely. Adding one outcome code to the analysis surfaces a channel roughly a third the size of denial itself.

---

## 11. Pricing, not just access

For loans that were actually originated, `rate_spread` is the difference between the APR and the market benchmark rate, so it measures price rather than access.

| group | originated with a spread | mean spread | median spread |
|---|---|---|---|
| Joint | 16,485 | 0.143 | 0.093 |
| Asian | 73,618 | 0.202 | 0.116 |
| White | 540,734 | 0.278 | 0.250 |
| Black or African American | 51,958 | **0.493** | **0.441** |

Black borrowers who were approved paid a spread 1.8 times the White mean and 1.8 times the White median. The median matters more than the mean here, because a mean can be moved by a handful of extreme loans and a median cannot. Note also that this is a conditional comparison on a selected group: these are the applicants who got through, which if anything understates the effect.

---

## 12. What this analysis cannot say

Stated here rather than at the end of a press release.

**There is no credit score in HMDA.** The regulator does not collect it. It is the single strongest legitimate predictor of a credit decision and it is absent from every number above. So no finding here is causal, and none of it establishes discrimination, which is a legal conclusion requiring evidence this dataset does not contain.

What the data does support is narrower and still substantial: the disparity is not explained by income, product, neighbourhood or lender choice, because it persists after holding each of those constant. Whether it is explained by creditworthiness cannot be tested with this data, and any conclusion in either direction is an assumption rather than a finding.

**Race is unreported for 24.5 percent of applications.** Every group comparison is computed on the three quarters who reported. The direction of that bias is unknown.

**Vintages are mixed.** 2022 is a Three Year file, 2023 and 2024 are One Year files, 2025 is provisional. Some of any year-on-year movement is filing completeness. Phase 01 section 4 has the detail.

**One state.** New York is not the United States.

---

## 13. The SQL this phase actually exercises

| technique | where it earns its place |
|---|---|
| Window functions | shift-share weights, percentile ranks, lender-versus-market comparisons |
| `FILTER (WHERE ...)` aggregates | every rate in this document, computed in one pass instead of self-joins |
| `GROUPING SETS` / rollups | denial rates by year, product and group in a single result |
| CTEs, several deep | the shift-share decomposition and the within-tract comparison |
| `percentile_cont` ordered-set aggregates | median spreads, and the quartiles in section 9 |
| Bridge-table joins | anything counting individual reported races rather than `derived_race` |
| Partial indexes and partition pruning | phase 09 shows the plans |
| Correlated `EXISTS` | the assertion queries in phase 07 |

Every query in this phase runs against the views from phase 05, so none of them contains a raw code literal such as `'3'` outside the definition of `is_denied`.

---

## 14. What is worth defending in a review

| choice | the alternative | why this one |
|---|---|---|
| `denied / (originated + denied)` | denied over all applications | the other six outcomes are not credit decisions |
| Shift-share before explaining a trend | a plausible narrative | my own plausible narrative was backwards |
| Within-tract comparison | tract minority share as a control | holds the neighbourhood constant by construction, not by regression |
| Per-lender comparison | market aggregate | rules out the single-outlier explanation |
| Reporting the incompleteness channel | denial rates only | a factor of 142 between lenders is not a footnote |
| Median as well as mean on pricing | mean alone | a mean on a skewed distribution is movable by a few loans |
| Stating the missing credit score repeatedly | one caveat at the end | it is the boundary of every claim here, not a disclaimer |
