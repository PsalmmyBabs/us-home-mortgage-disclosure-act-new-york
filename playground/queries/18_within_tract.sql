-- Phase 08 finding 6: the gap survives the neighbourhood.
WITH t AS (
  SELECT f.census_tract,
    100.0*count(*) FILTER (WHERE f.action_taken='3' AND a.derived_race='Black or African American')
      /nullif(count(*) FILTER (WHERE a.derived_race='Black or African American'),0) AS rb,
    100.0*count(*) FILTER (WHERE f.action_taken='3' AND a.derived_race='White')
      /nullif(count(*) FILTER (WHERE a.derived_race='White'),0)                     AS rw
  FROM marts.fct_application f
  JOIN marts.dim_applicant_profile a ON a.applicant_profile_sk = f.applicant_profile_sk
  WHERE f.action_taken IN ('1','3') AND f.census_tract <> 'UNKNOWN'
    AND a.derived_race IN ('White','Black or African American')
  GROUP BY 1
  HAVING count(*) FILTER (WHERE a.derived_race='Black or African American') >= 100
     AND count(*) FILTER (WHERE a.derived_race='White') >= 100)
SELECT count(*)                                  AS tracts,
       count(*) FILTER (WHERE rb > rw)           AS black_rate_higher,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (ORDER BY rb-rw) AS numeric), 1) AS median_gap_points
FROM t;
