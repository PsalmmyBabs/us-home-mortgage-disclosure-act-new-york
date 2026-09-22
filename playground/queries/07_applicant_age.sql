-- General analysis section 6: the applicant age funnel.
-- 8888 is HMDA's code for an age that was not provided. It is kept as its own
-- band rather than dropped, because it turns out not to be a demographic at all:
-- 84 percent of those originations are business or commercial purpose lending,
-- where the borrower is a company and has no age to report.
WITH d AS (
  SELECT CASE WHEN a.applicant_age = '8888'              THEN '7 Age not provided'
              WHEN a.applicant_age IN ('65-74','>74')    THEN '6 65 and above'
              WHEN a.applicant_age = '<25'               THEN '1 Under 25'
              WHEN a.applicant_age = '25-34'             THEN '2 25-34'
              WHEN a.applicant_age = '35-44'             THEN '3 35-44'
              WHEN a.applicant_age = '45-54'             THEN '4 45-54'
              WHEN a.applicant_age = '55-64'             THEN '5 55-64'
         END AS age_band, f.action_taken, f.loan_amount
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken <> '6')
SELECT age_band,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct_of_applications,
       count(*) FILTER (WHERE action_taken IN ('1','2'))  AS approved,
       round(CAST(100.0*count(*) FILTER (WHERE action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN action_taken IN ('1','2') THEN loan_amount END)
             AS numeric))                                AS median_approved_loan,
       round(CAST(sum(loan_amount) FILTER (WHERE action_taken = '1') AS DECIMAL(24,4))
             / 1000000000, 2)                             AS total_disbursed_bn
FROM d GROUP BY 1 ORDER BY 1;
