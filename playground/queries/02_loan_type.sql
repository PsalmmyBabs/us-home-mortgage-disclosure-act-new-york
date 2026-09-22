-- General analysis section 2: which products carry this market.
SELECT c.label                                           AS loan_type,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2') THEN f.loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM marts.fct_application f
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
JOIN ref.ref_code c ON c.code_field = 'loan_type' AND c.code_value = p.loan_type
WHERE f.action_taken <> '6'
GROUP BY 1 ORDER BY 2 DESC, 1;
