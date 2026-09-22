-- General analysis section 9: what borrowing costs.
-- Restricted to 2025 and to originated loans. Both restrictions are load
-- bearing. A rate exists only on a loan that was actually made, and the median
-- rate moved from 4.375 percent in 2022 to 6.875 in 2024, so pooling the four
-- years would measure the rate environment rather than the product.
SELECT c.label                                           AS loan_purpose,
       count(*)                                          AS loans,
       round(CAST(avg(f.interest_rate) AS numeric), 3)    AS mean_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (ORDER BY f.interest_rate)
             AS numeric), 3)                             AS median_rate
FROM marts.fct_application f
JOIN marts.dim_loan_product p ON p.loan_product_sk = f.loan_product_sk
JOIN ref.ref_code c ON c.code_field = 'loan_purpose' AND c.code_value = p.loan_purpose
WHERE f.action_taken = '1'
  AND f.interest_rate IS NOT NULL
  AND f.activity_year = 2025
GROUP BY 1 ORDER BY 4, 1;
