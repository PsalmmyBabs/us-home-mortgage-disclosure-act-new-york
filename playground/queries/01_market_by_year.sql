-- General analysis section 1: the market, 2022 to 2025.
-- Purchased loans (action_taken 6) are excluded from every funnel table in the
-- general analysis: they are loans another lender already made, so there was no
-- application here to approve.
SELECT activity_year,
       count(*)                                          AS applications,
       count(*) FILTER (WHERE action_taken IN ('1','2'))  AS approved,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(sum(loan_amount) FILTER (WHERE action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM marts.fct_application
WHERE action_taken <> '6'
GROUP BY 1 ORDER BY 1;
