-- Phase 08 finding 2: mix effect against within-product effect, 2022 to 2023.
WITH y AS (
  SELECT f.activity_year AS yr, p.loan_purpose,
         count(*) FILTER (WHERE f.action_taken IN ('1','3')) AS decided,
         count(*) FILTER (WHERE f.action_taken = '3')        AS denied
  FROM marts.fct_application f
  JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
  WHERE f.activity_year IN (2022, 2023)
  GROUP BY 1,2),
t AS (SELECT yr, sum(decided) AS tot FROM y GROUP BY 1),
j AS (SELECT y.loan_purpose,
        max(CASE WHEN yr=2022 THEN 1.0*y.decided/t.tot   END) AS w22,
        max(CASE WHEN yr=2023 THEN 1.0*y.decided/t.tot   END) AS w23,
        max(CASE WHEN yr=2022 THEN 1.0*y.denied/y.decided END) AS r22,
        max(CASE WHEN yr=2023 THEN 1.0*y.denied/y.decided END) AS r23
      FROM y JOIN t USING (yr) GROUP BY 1)
SELECT round(100*sum((w23-w22)*r22), 3) AS mix_effect,
       round(100*sum(w23*(r23-r22)), 3) AS within_effect,
       round(100*(sum((w23-w22)*r22) + sum(w23*(r23-r22))), 3) AS total_change
FROM j;
