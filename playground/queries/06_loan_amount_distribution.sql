-- General analysis section 5: loan size, approved loans only.
-- The mean sits far above the median in every year, which is the signature of
-- a right-skewed distribution: a few very large loans, most of them small.
SELECT activity_year,
       count(*)                                                       AS approved,
       round(CAST(percentile_cont(0.10) WITHIN GROUP (ORDER BY loan_amount) AS numeric)) AS p10,
       round(CAST(percentile_cont(0.25) WITHIN GROUP (ORDER BY loan_amount) AS numeric)) AS p25,
       round(CAST(percentile_cont(0.50) WITHIN GROUP (ORDER BY loan_amount) AS numeric)) AS median,
       round(CAST(percentile_cont(0.75) WITHIN GROUP (ORDER BY loan_amount) AS numeric)) AS p75,
       round(CAST(percentile_cont(0.90) WITHIN GROUP (ORDER BY loan_amount) AS numeric)) AS p90,
       round(CAST(avg(loan_amount) AS numeric))                       AS mean
FROM marts.fct_application
WHERE action_taken IN ('1','2')
GROUP BY 1 ORDER BY 1;
