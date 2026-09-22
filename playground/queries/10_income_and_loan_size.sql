-- General analysis section 8: income against loan size.
-- Two questions in one result: the level (what does a typical applicant at this
-- income borrow) and the spread (how wide is the range within one income band).
WITH d AS (
  SELECT CASE WHEN income_thousands IS NULL THEN '6 not reported'
              WHEN income_thousands <  50   THEN '1 under 50k'
              WHEN income_thousands < 100   THEN '2 50-100k'
              WHEN income_thousands < 150   THEN '3 100-150k'
              WHEN income_thousands < 200   THEN '4 150-200k'
              ELSE                               '5 200k and above'
         END AS income_band, action_taken, loan_amount
  FROM marts.fct_application
  WHERE action_taken <> '6')
SELECT income_band,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.25) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS p25_approved,
       round(CAST(percentile_cont(0.50) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(percentile_cont(0.75) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS p75_approved,
       round(CAST(sum(loan_amount) FILTER (WHERE action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM d GROUP BY 1 ORDER BY 1;
