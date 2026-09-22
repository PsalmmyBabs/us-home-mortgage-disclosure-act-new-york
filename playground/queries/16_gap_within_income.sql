-- Phase 08 finding 4: the gap survives income.
WITH d AS (
  SELECT f.action_taken, f.income_thousands, a.derived_race
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3') AND f.activity_year = 2025
    AND f.income_thousands IS NOT NULL
    AND a.derived_race IN ('White','Black or African American'))
SELECT CASE WHEN income_thousands <  50 THEN '1. under 50k'
            WHEN income_thousands < 100 THEN '2. 50-100k'
            WHEN income_thousands < 150 THEN '3. 100-150k'
            WHEN income_thousands < 200 THEN '4. 150-200k'
            ELSE                             '5. 200k+' END AS income_band,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND derived_race='Black or African American')
             /nullif(count(*) FILTER (WHERE derived_race='Black or African American'),0),1) AS black_denial,
       round(100.0*count(*) FILTER (WHERE action_taken='3' AND derived_race='White')
             /nullif(count(*) FILTER (WHERE derived_race='White'),0),1)                     AS white_denial
FROM d GROUP BY 1 ORDER BY 1;
