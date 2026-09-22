-- General analysis section 4: how long the loans run.
-- 30 years and above is one band on purpose: terms beyond 360 months are rare
-- and behave like 30-year lending rather than like a separate product.
WITH d AS (
  SELECT CASE WHEN loan_term_months IS NULL      THEN '6 not reported'
              WHEN loan_term_months <= 120       THEN '1 up to 10 years'
              WHEN loan_term_months <= 180       THEN '2 10 to 15 years'
              WHEN loan_term_months <= 240       THEN '3 15 to 20 years'
              WHEN loan_term_months <  360       THEN '4 20 to under 30 years'
              ELSE                                    '5 30 years and above'
         END AS term_band, action_taken, loan_amount
  FROM marts.fct_application
  WHERE action_taken <> '6')
SELECT term_band,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct,
       count(*) FILTER (WHERE action_taken IN ('1','2'))  AS approved,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(sum(loan_amount) FILTER (WHERE action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM d GROUP BY 1 ORDER BY 1;
