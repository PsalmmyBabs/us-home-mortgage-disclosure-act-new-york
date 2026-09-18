-- Phase 08 finding 3: outcomes by applicant group, latest year.
SELECT a.derived_race,
       count(*)                                                        AS decided,
       round(100.0*count(*) FILTER (WHERE f.action_taken='3')/count(*),1) AS denial_pct
FROM marts.fct_application f
JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
WHERE f.action_taken IN ('1','3') AND f.activity_year = 2025
GROUP BY 1
ORDER BY 2 DESC;
