-- General analysis section 12: the sex by race funnel.
-- Descriptive, not a disparity claim. The outcome gaps and what survives
-- controlling for income, product, neighbourhood and lender are in
-- docs/08b_analysis_disparity.md.
SELECT a.derived_sex, a.derived_race,
       count(*)                                          AS applications,
       count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS approved,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2') THEN f.loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(coalesce(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken <> '6'
  AND a.derived_sex  IN ('Male','Female','Joint')
  AND a.derived_race IN ('White','Black or African American','Asian','Joint')
GROUP BY 1,2 ORDER BY 1, 3 DESC, 2;
