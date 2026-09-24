# Phase 08: The analysis

What this market is, who borrows in it, what they borrow for, how much they get and what it costs them.

Every table below comes from a query you can run yourself. The query number links to the browser playground, which opens with that query loaded and already executed against all 1.75 million rows. If you think a number is wrong, you can check it in about ten seconds.

The outcome gaps between applicant groups, and what survives controlling for income, product, neighbourhood and lender, are a separate document: [phase 08b](08b_analysis_disparity.md).

---

## 1. Two decisions that come before every number

**Purchased loans are not applications.** 158,170 rows in this dataset have `action_taken = 6`, meaning the filer bought a loan another lender had already made. Nobody applied to anyone. Counting them in an application funnel is like counting a house you bought as a house you failed to build, and it does real damage: they are 70 percent of the rows where applicant age is unreported, and leaving them in made that band's approval rate read 19.9 percent instead of 66.9. Every funnel table in this document excludes them.

**Approved means the lender said yes.** That is `action_taken` 1, originated, plus 2, approved but not accepted. In the second case the lender approved and the applicant walked away, which is still an approval. *Total disbursed* is originated only, because that is money that actually left the building. The two differ by about one percentage point everywhere, and the definitions are stated on every table rather than assumed.

So the funnel in this document is: **applications → approved → disbursed.**

| | |
|---|---|
| Published rows | 1,755,419 |
| Modelled | 1,754,846 |
| Purchased loans, excluded from the funnel | 158,170 |
| **Applications** | **1,596,676** |
| Approved | 996,548 |
| Disbursed | 371.42bn |

---

## 2. Finding 1: the market lost a third of its volume and has not got it back

[▶ query 01](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=01)

```sql
SELECT activity_year,
       count(*)                                          AS applications,
       count(*) FILTER (WHERE action_taken IN ('1','2'))  AS approved,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)  AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(sum(loan_amount) FILTER (WHERE action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                            AS disbursed_bn
FROM marts.fct_application
WHERE action_taken <> '6'
GROUP BY 1 ORDER BY 1;
```

| year | applications | approved | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| 2022 | 500,553 | 321,416 | **64.2%** | 255,000 | 128.52bn |
| 2023 | 346,943 | 213,183 | 61.4% | 215,000 | 72.70bn |
| 2024 | 355,249 | 218,756 | 61.6% | 235,000 | 76.89bn |
| 2025 | 393,931 | 243,193 | 61.7% | 255,000 | 93.31bn |

Applications fell 31 percent in a single year and dollars fell 43 percent, which is the larger fall because the median loan shrank at the same time. By 2025 volume has recovered to 79 percent of 2022 and dollars to 73 percent.

**The approval rate is the part that did not recover.** It dropped 2.8 points in 2023 and has sat within 0.3 points of the new level for three years. Demand came back; the willingness to say yes did not. Phase 08b section 3 decomposes that move and shows it was products denying more rather than a change in what people applied for.

---

## 3. Finding 2: nine tenths of this market is one product, and half the money is one purpose

[▶ query 02](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=02) · [▶ query 03](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=03)

| loan type | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| Conventional | 1,434,757 | **89.9%** | 62.6% | 235,000 | 338.38bn |
| FHA insured | 123,790 | 7.8% | 60.0% | 285,000 | 25.44bn |
| VA guaranteed | 36,199 | 2.3% | 63.1% | 275,000 | 7.40bn |
| RHS or FSA guaranteed | 1,930 | 0.1% | 73.3% | 145,000 | 0.20bn |

| loan purpose | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| Home purchase | 733,126 | 45.9% | **72.2%** | 345,000 | **240.49bn** |
| Home improvement | 247,663 | 15.5% | 51.9% | 85,000 | 15.94bn |
| Cash-out refinancing | 231,963 | 14.5% | 56.8% | 235,000 | 48.55bn |
| Other purpose | 195,592 | 12.2% | 47.8% | 95,000 | 17.45bn |
| Refinancing | 188,094 | 11.8% | 60.3% | 205,000 | 48.89bn |
| Not applicable | 238 | 0.0% | 64.3% | 215,000 | 0.09bn |

**Purpose tells you far more than type does.** The four loan types span 13.3 points, but the spread only looks wide because of RHS at 1,930 applications: conventional and FHA together are 97.7 percent of the market and sit 2.6 points apart. Purpose spans 24.4 points, from 72.2 percent on a home purchase to 47.8 percent on "other purpose".

And the money concentrates harder than the volume. Home purchase is 46 percent of applications and **65 percent of the dollars**. Home improvement is the mirror image: 15.5 percent of applications and 4.3 percent of the dollars, on a median loan of 85,000, with the second lowest approval rate in the table. A lender running a portfolio here is running two different businesses that happen to share a regulator.

---

## 4. Finding 3: a quarter of this market sits behind someone else's claim

[▶ query 04](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=04)

Lien position is the single most informative structural field HMDA publishes. A first lien is repaid first if the property is sold or foreclosed. A subordinate lien is repaid only after the first lien is satisfied, which is why it is priced and underwritten differently.

| lien position | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| Secured by a first lien | 1,178,483 | 73.8% | **65.7%** | 305,000 | 344.78bn |
| Secured by a subordinate lien | 418,193 | 26.2% | **53.1%** | 85,000 | 26.64bn |

Alongside it, from the same junk dimension:

| | applications | share | approval rate |
|---|---|---|---|
| Open-end line of credit | 402,611 | 25.2% | 53.0% |
| Business or commercial purpose | 130,382 | 8.2% | 62.9% |
| Nonconforming | 66,938 | 4.2% | 63.4% |
| Reverse mortgage | 4,767 | 0.3% | 68.6% |

**Second-lien and open-end lending is a quarter of this market and 7 percent of its money.** Approved 12.6 points less often, for a median loan less than a third the size. The overlap between the two rows is almost total: these are home equity lines, and they are what the home improvement purpose in section 3 is mostly made of.

**What is not here, and why.** HMDA also publishes `balloon_payment`, `interest_only_payment`, `negative_amortization`, `other_nonamortizing_features` and `prepayment_penalty_term`. Those are the structural features that matter most for credit risk, and they are the ones that defined 2008. They exist in `raw.raw_lar` in this project and were not carried into the model. That is a real gap, it is deliberate rather than accidental, and closing it means a migration, a fact table reload and a fresh Parquet export. It is the first thing I would add.

---

## 5. Finding 4: two thirds of applications are for exactly thirty years

[▶ query 05](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=05)

| term | applications | share | approved | approval rate | median approved | disbursed |
|---|---|---|---|---|---|---|
| Up to 10 years | 87,744 | 5.5% | 55,296 | 63.0% | 75,000 | 26.66bn |
| 10 to 15 years | 99,504 | 6.2% | 66,102 | 66.4% | 125,000 | 16.84bn |
| 15 to 20 years | 130,141 | 8.2% | 73,333 | **56.3%** | 105,000 | 11.02bn |
| 20 to under 30 years | 115,651 | 7.2% | 63,309 | **54.7%** | 115,000 | 11.00bn |
| **30 years and above** | **1,078,159** | **67.5%** | 684,349 | 63.5% | 315,000 | **290.13bn** |
| Not reported | 85,477 | 5.4% | 54,159 | 63.4% | 125,000 | 15.77bn |

1,062,501 applications are for exactly 360 months. Terms beyond 360 are rare and behave like 30-year lending, so they sit in the same band.

**The 30-year mortgage is 67.5 percent of applications and 78 percent of the money.** Everything else is a rounding error by value.

The interesting row is the one in the middle. The 15 to 30 year bands approve at 56.3 and 54.7 percent, the two worst in the table, and worse than both the shorter and the longer terms around them. That is not a term effect, it is a composition effect: those bands are where the second-lien and home improvement lending sits, and section 4 already showed what that does to an approval rate. Shorter terms are small secured loans that clear easily; 30 years is a first mortgage on a purchase. The middle is neither.

---

## 6. Finding 5: the average loan is not a loan anyone gets

[▶ query 06](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=06)

Approved loans only.

| year | p10 | p25 | median | p75 | p90 | **mean** |
|---|---|---|---|---|---|---|
| 2022 | 65,000 | 125,000 | 255,000 | 485,000 | 785,000 | **417,647** |
| 2023 | 55,000 | 105,000 | 215,000 | 455,000 | 705,000 | **358,277** |
| 2024 | 55,000 | 105,000 | 235,000 | 475,000 | 735,000 | **368,593** |
| 2025 | 65,000 | 125,000 | 255,000 | 505,000 | 795,000 | **401,264** |

**The mean sits above the 60th percentile in every year.** In 2025 the average approved loan is 401,264 and the median is 255,000, a gap of 57 percent. That is the signature of a right-skewed distribution: a small number of very large loans pulling the average away from anything typical. Any headline quoting a mortgage "average" in this market is describing a loan most borrowers do not get, which is why every other table in this document uses the median.

The spread also widened faster than the middle moved. Between 2023 and 2025 the median rose 40,000 while the 90th percentile rose 90,000.

**One thing to know about these numbers.** There are only **923 distinct loan amounts** across 951,371 originated loans, and 99.8 percent are exact multiples of 5,000. The Bureau rounds loan amounts before publication to protect applicant privacy. Every median here will land on a round number, and a histogram of this column is spiky by construction. That is the data, not a bug, and it is why loan amount is never used here for anything finer than a percentile.

---

## 7. Finding 6: approval falls with every decade of age, and so does loan size

[▶ query 07](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=07)

| age band | applications | % of applications | approved | approval rate | median approved loan | total disbursed |
|---|---|---|---|---|---|---|
| Under 25 | 35,382 | 2.2% | 24,327 | **68.8%** | 195,000 | 6.35bn |
| 25-34 | 299,818 | 18.8% | 206,168 | **68.8%** | 285,000 | 75.39bn |
| 35-44 | 396,860 | 24.9% | 254,134 | 64.0% | **295,000** | **103.03bn** |
| 45-54 | 338,638 | 21.2% | 204,910 | 60.5% | 225,000 | 70.79bn |
| 55-64 | 272,665 | 17.1% | 158,708 | 58.2% | 185,000 | 44.64bn |
| 65 and above | 195,509 | 12.2% | 109,652 | **56.1%** | 155,000 | 25.49bn |
| Age not provided | 57,804 | 3.6% | 38,649 | 66.9% | **565,000** | 45.71bn |

**Approval falls monotonically, 12.7 points from 25-34 down to 65 and above, and the median loan falls with it from 295,000 to 155,000.** Older applicants ask for less and hear no more often. Both movements are clean, neither reverses, and the 35-44 band alone writes 103bn, more than the two oldest bands combined.

**The not-provided row is not a demographic.** HMDA codes an unreported age as `8888`, and it would be easy to drop it. Checking it first pays off:

| | age not provided | every other band |
|---|---|---|
| Business or commercial purpose | **84.3%** | 5.1% |
| Multifamily property | **36.5%** | 0.1% |

These are companies. A limited partnership buying an apartment building has no applicant age to report, which is why the median approved loan is 565,000 against 155,000 to 295,000 everywhere else. Reported as its own band rather than excluded, because the alternative is silently removing 45.71bn of commercial lending from a market analysis.

---

## 8. Finding 7: a second name on the application is worth eight points

[▶ query 08](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=08)

Descriptive only. Whether these gaps survive income, product, neighbourhood and lender is [phase 08b](08b_analysis_disparity.md), and the answer there is not the same as the answer here.

| applicant sex | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| Male | 557,903 | 34.9% | 58.9% | 225,000 | 111.93bn |
| Joint | 505,023 | 31.6% | **69.5%** | 265,000 | 130.91bn |
| Female | 371,627 | 23.3% | 59.6% | 195,000 | 59.60bn |
| Sex not available | 162,123 | 10.2% | 58.9% | 335,000 | 68.97bn |

| applicant race | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| White | 983,251 | 61.6% | 66.0% | 205,000 | 198.23bn |
| Race not available | 299,190 | 18.7% | 56.9% | 315,000 | 98.89bn |
| Asian | 147,339 | 9.2% | 62.1% | **455,000** | 44.13bn |
| Black or African American | 124,980 | 7.8% | 49.5% | 255,000 | 19.63bn |
| Joint | 27,293 | 1.7% | 68.0% | 355,000 | 8.86bn |
| American Indian or Alaska Native | 6,829 | 0.4% | 41.9% | 165,000 | 0.67bn |

Crossing the two, which is the pivot [query 08](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=08) returns:

<table>
<thead>
<tr><th rowspan="2">applicant sex</th><th rowspan="2">race</th><th colspan="2">volume</th><th colspan="3">outcome</th></tr>
<tr><th>applications</th><th>approved</th><th>approval rate</th><th>median approved</th><th>disbursed</th></tr>
</thead>
<tbody>
<tr><td rowspan="4">Joint</td><td>White</td><td align="right">365,685</td><td align="right">263,755</td><td align="right"><b>72.1%</b></td><td align="right">235,000</td><td align="right">89.01bn</td></tr>
<tr><td>Joint</td><td align="right">24,671</td><td align="right">16,849</td><td align="right">68.3%</td><td align="right">345,000</td><td align="right">8.05bn</td></tr>
<tr><td>Asian</td><td align="right">41,291</td><td align="right">26,624</td><td align="right">64.5%</td><td align="right">515,000</td><td align="right">14.83bn</td></tr>
<tr><td>Black or African American</td><td align="right">26,190</td><td align="right">14,828</td><td align="right">56.6%</td><td align="right">425,000</td><td align="right">6.02bn</td></tr>
<tr><td rowspan="4">Female</td><td>Asian</td><td align="right">41,146</td><td align="right">26,329</td><td align="right">64.0%</td><td align="right">405,000</td><td align="right">11.29bn</td></tr>
<tr><td>White</td><td align="right">234,089</td><td align="right">147,402</td><td align="right">63.0%</td><td align="right">165,000</td><td align="right">34.15bn</td></tr>
<tr><td>Joint</td><td align="right">999</td><td align="right">651</td><td align="right">65.2%</td><td align="right">335,000</td><td align="right">0.26bn</td></tr>
<tr><td>Black or African American</td><td align="right">52,701</td><td align="right">25,886</td><td align="right">49.1%</td><td align="right">225,000</td><td align="right">7.43bn</td></tr>
<tr><td rowspan="4">Male</td><td>White</td><td align="right">377,850</td><td align="right">234,748</td><td align="right">62.1%</td><td align="right">205,000</td><td align="right">74.22bn</td></tr>
<tr><td>Joint</td><td align="right">1,530</td><td align="right">996</td><td align="right">65.1%</td><td align="right">455,000</td><td align="right">0.53bn</td></tr>
<tr><td>Asian</td><td align="right">64,088</td><td align="right">38,093</td><td align="right">59.4%</td><td align="right">435,000</td><td align="right">17.83bn</td></tr>
<tr><td>Black or African American</td><td align="right">45,136</td><td align="right">20,875</td><td align="right"><b>46.2%</b></td><td align="right">215,000</td><td align="right">6.09bn</td></tr>
</tbody>
</table>

**The range across this table is 25.9 points, from 72.1 percent to 46.2 percent.** Two patterns run through it and they are independent of each other. A jointly named application is approved roughly 8 points more often than a single applicant of the same race, in every race group. And within each sex, the ordering of race is identical.

Product choice differs sharply too, which matters because it is the mechanism behind a lot of what follows:

| group | conventional | FHA | VA | home purchase | subordinate lien |
|---|---|---|---|---|---|
| Black or African American | 78.3% | **18.6%** | 3.0% | 40.4% | 29.2% |
| American Indian or Alaska Native | 87.1% | 8.9% | 3.7% | 37.2% | 34.5% |
| White | 90.4% | 7.1% | 2.4% | 43.0% | 28.8% |
| Asian | **96.0%** | 3.5% | 0.5% | **67.6%** | 15.8% |

Black applicants use FHA at five times the Asian rate. Asian applicants are on a home purchase two thirds of the time against Black applicants two fifths. Those are different products with different approval rates and different prices, and any comparison that ignores them is comparing the wrong things.

---

## 9. Finding 8: the biggest market has the lowest approval rate

[▶ query 09](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=09)

| area | applications | share | approval rate | median approved | disbursed |
|---|---|---|---|---|---|
| New York-Jersey City-White Plains | 482,104 | 30.2% | **58.3%** | 495,000 | **184.86bn** |
| Nassau County-Suffolk County | 325,669 | 20.4% | 59.5% | 405,000 | 87.51bn |
| Outside any metropolitan area | 145,478 | 9.1% | 60.6% | 135,000 | 15.29bn |
| Rochester | 130,901 | 8.2% | **71.7%** | 135,000 | 15.06bn |
| Buffalo-Cheektowaga | 121,972 | 7.6% | 68.4% | 165,000 | 16.16bn |
| Albany-Schenectady-Troy | 113,855 | 7.1% | 65.9% | 185,000 | 15.62bn |
| Syracuse | 71,962 | 4.5% | 68.8% | 135,000 | 8.17bn |
| Poughkeepsie-Newburgh-Middletown | 45,897 | 2.9% | 61.8% | 255,000 | 7.64bn |
| Kiryas Joel-Poughkeepsie-Newburgh | 40,485 | 2.5% | 63.4% | 265,000 | 7.32bn |
| Utica-Rome | 30,141 | 1.9% | 68.2% | 125,000 | 2.89bn |

**New York City is 30 percent of the state's applications, 50 percent of its lending by value, and the lowest approval rate in the table.** The two downstate markets together are half the applications and 73 percent of the money.

The ranking by volume and the ranking by dollars are genuinely different lists. Rochester is fourth by applications and sixth by dollars. Buffalo is fifth by applications and third by dollars. A capacity plan built on application counts and a balance sheet built on exposure would point at different offices.

Upstate approves far more readily, 71.7 percent in Rochester against 58.3 in New York City, on a median loan less than a third the size. That is mostly price: the same borrower profile is a much larger loan-to-income multiple in a 495,000 market than in a 135,000 one.

**A portability bug found while building this table.** PostgreSQL sorts NULLs *first* on `ORDER BY ... DESC`; DuckDB sorts them *last*. Three MSAs with one or two applications and no dollars floated to the top of the by-dollars list in Postgres and not in DuckDB. No error in either engine, just a different top ten. The query now says `NULLS LAST` explicitly. Phase 10 has the full list of these.

---

## 10. Finding 9: income sets the size of the loan, not the multiple

[▶ query 10](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=10)

| income band | applications | share | approval rate | p25 | median | p75 | disbursed |
|---|---|---|---|---|---|---|---|
| under 50k | 160,387 | 10.0% | **46.0%** | 65,000 | 105,000 | 165,000 | 11.76bn |
| 50-100k | 428,470 | 26.8% | 60.5% | 85,000 | 155,000 | 235,000 | 43.11bn |
| 100-150k | 349,698 | 21.9% | 65.1% | 115,000 | 245,000 | 405,000 | 60.48bn |
| 150-200k | 204,876 | 12.8% | **67.1%** | 155,000 | 325,000 | 525,000 | 47.04bn |
| 200k and above | 339,585 | 21.3% | 66.2% | 255,000 | 505,000 | 815,000 | **145.76bn** |
| not reported | 113,660 | 7.1% | 64.9% | 215,000 | 465,000 | 905,000 | 63.27bn |

And the same approved loans expressed as a multiple of income:

| income band | p25 | median | p75 |
|---|---|---|---|
| under 50k | 1.56 | **2.62** | 3.71 |
| 50-100k | 1.15 | 2.16 | 3.15 |
| 100-150k | 0.96 | 2.03 | 3.35 |
| 150-200k | 0.87 | 1.92 | 3.08 |
| 200k and above | 0.73 | **1.53** | 2.46 |

**The level rises with income and the multiple falls.** An applicant under 50,000 borrows 2.62 times their income; one over 200,000 borrows 1.53 times. Higher earners take proportionally less leverage, which is the opposite of what a naive reading of the first table suggests.

The spread widens enormously alongside it. The middle half of the bottom band is 65,000 to 165,000, a 100,000 window. The middle half of the top band is 255,000 to 815,000, a 560,000 window. Income predicts loan size well at the bottom and poorly at the top, where property choice and equity matter more than salary.

**Approval stops improving after 150k.** It climbs 21 points from the bottom band to 150-200k, then falls back slightly. Money buys approval up to a point and then stops buying it, which makes the top band a useful control in phase 08b: if a gap survives at 200,000 of income, income is not what is producing it.

---

## 11. Finding 10: the rate environment swamps the product

[▶ query 11](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=11)

Originated loans only, because a rate exists only on a loan that was actually made. Coverage is **96.4 percent** of originations, stable across all four years, and the missing 3.6 percent is concentrated in exempt filers rather than spread evenly.

| year | loans | median rate |
|---|---|---|
| 2022 | 295,588 | **4.375%** |
| 2023 | 195,869 | 6.750% |
| 2024 | 201,572 | **6.875%** |
| 2025 | 224,073 | 6.625% |

**A 250 basis point move in twelve months.** Nothing else in this document comes close, and it is why every cut below is computed within a single year. Pooling four years would measure which products were popular in 2022, not how products are priced.

2025 only:

| loan purpose | loans | mean rate | median rate |
|---|---|---|---|
| Refinancing | 25,772 | 6.585% | **6.490%** |
| Home purchase | 115,778 | 6.594% | 6.500% |
| Home improvement | 29,853 | 6.883% | 6.940% |
| Cash-out refinancing | 29,913 | 7.284% | 6.990% |
| Other purpose | 22,728 | 7.057% | **7.000%** |

| loan type, 2025 | median rate | | income band, 2025 | median rate |
|---|---|---|---|---|
| VA | **6.250%** | | under 50k | **6.875%** |
| FHA | 6.375% | | 50-100k | 6.550% |
| RHS or FSA | 6.375% | | 100-150k | 6.575% |
| Conventional | 6.625% | | 150-200k | 6.625% |
| | | | 200k and above | **6.500%** |

Three things fall out of this. **Government guaranteed paper is cheaper**, 37.5 basis points between VA and conventional, which is what the guarantee is for. **Purpose matters more than type**, a 51 basis point spread against 37.5. And **the lowest income band pays 37.5 basis points more than the highest**, which is the same size as the entire VA discount.

Cash-out refinancing is the row worth a second look: its median is 6.990 but its mean is 7.284, the largest mean-to-median gap in the table. Something in that product has a long right tail that the others do not.

---

## 12. Finding 11: more than a third of denials are one reason

[▶ query 12](https://samuelbabajide.github.io/us-home-mortgage-disclosure-act-new-york/playground/#q=12)

HMDA lets a filer record up to four denial reasons. This project keeps them in a bridge table, `marts.br_denial_reason`, because flattening four optional reasons into four columns on the fact table would break first normal form. 78.3 percent of denials give one reason, 17.9 percent give two, 3.4 percent three and 0.5 percent all four.

Primary reason, on genuinely denied applications:

| primary reason | denials | share |
|---|---|---|
| **Debt-to-income ratio** | 117,389 | **36.7%** |
| Credit history | 74,093 | 23.2% |
| Collateral | 53,373 | 16.7% |
| Other | 30,692 | 9.6% |
| Credit application incomplete | 21,413 | 6.7% |
| Unverifiable information | 9,205 | 2.9% |
| Insufficient cash (downpayment, closing costs) | 5,657 | 1.8% |
| *Exempt (code 1111, unmapped)* | 4,533 | 1.4% |
| Employment history | 3,037 | 1.0% |
| Mortgage insurance denied | 81 | 0.0% |

**Debt-to-income is the single largest reason at 36.7 percent, and on its own it is almost as large as credit history and collateral together at 39.9.** That is worth sitting with, because it reframes the affordability question: the binding constraint in this market is more often what the applicant already owes than what they have previously repaid badly.

Two data problems are visible in this table rather than hidden.

**21,665 originated loans carry a denial reason.** The loan was made, and a reason for refusing it was filed alongside. That is a filer error, it is in the published data, and it is why this query restricts to `action_taken = '3'` instead of trusting the bridge alone. Phase 07's assertion framework should be catching this and is not.

**Code 1111 has no label.** 31,821 denial-reason rows carry HMDA's "Exempt" value and `ref.ref_code` has no mapping for it, so the labelled view returns NULL. Blanking those rows would have quietly removed 4,533 primary reasons from this table, so the code is named instead. This is the same class of gap as the `applicant_credit_score_type` one documented in phase 07 section 5, and it belongs in the `ref_code` seed.

---

## 13. What this analysis cannot say

**There is no credit score in HMDA.** The regulator does not collect it. It is the strongest legitimate predictor of a credit decision and it is absent from every number above. Nothing here is causal.

**Race is unreported for 18.7 percent of applications and sex for 10.2 percent.** Age is unreported for 3.6 percent, and section 7 shows that band is mostly companies rather than reticent people. The direction of the bias in the other two is unknown.

**Income is self-reported and rounded.** So are loan amounts, to the nearest 5,000. Loan-to-income multiples inherit both roundings.

**Vintages are mixed.** 2022 is a Three Year file, 2023 and 2024 are One Year files, 2025 is provisional. Some of the 2022 to 2023 fall is filing completeness rather than market movement. Phase 01 section 4 has the detail, and phase 08b section 3 shows what survives once that is accounted for.

---

## 14. The SQL this phase actually exercises

| technique | where it earns its place |
|---|---|
| `FILTER (WHERE ...)` aggregates | every rate and every conditional median here, in one pass instead of self-joins |
| `percentile_cont` ordered-set aggregates | medians and quartiles throughout, and the whole of section 6 |
| `percentile_cont` over a `CASE` | median of approved loans computed in the same pass as the count of all applications |
| Window functions | share-of-total columns without a second scan |
| Junk dimension joins | loan type, purpose, lien status and structure all come from one 194-row table |
| Bridge-table joins | section 12, because denial reasons are one-to-many |
| Generated views | `sync_views.py` writes `bootstrap.sql` from `pg_get_viewdef` so the browser build cannot drift from the database |
| Exact decimal arithmetic | `DECIMAL(24,8)` rather than float, because four of these queries returned different answers in the two engines until it was fixed |

---

## 15. What is worth defending in a review

| choice | the alternative | why this one |
|---|---|---|
| Excluding purchased loans from the funnel | counting every row as an application | nobody applied; including them made one age band read 19.9% instead of 66.9% |
| Approved = originated plus approved-not-accepted | originated only | the lender said yes in both cases; disbursed is reported separately for the money question |
| Median everywhere, mean only alongside it | the mean | the mean approved loan sits above the 60th percentile in every year |
| Keeping the not-provided bands in the table | filtering them out | the age one turned out to be 84% commercial lending, which is a finding, not noise |
| Interest rate cuts within a single year | pooling four years | the median rate moved 250 basis points between 2022 and 2024 |
| Reporting the 21,665 contradictory denial reasons | dropping them silently | it is a defect in the published data and the assertion suite should catch it |
| Naming unmapped code 1111 | letting it render blank | blanking it would have removed 4,533 denials from the table |
| `DECIMAL(24,8)` rather than float division | `/1e9` and `AS numeric` | the two engines disagreed in the second decimal place, and the parity test caught it |
| `NULLS LAST` written explicitly | relying on the default | the two engines have opposite defaults and neither raises an error |
