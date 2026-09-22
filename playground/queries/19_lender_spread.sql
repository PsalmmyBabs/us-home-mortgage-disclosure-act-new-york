-- Phase 08 finding 8: lenders differ from each other more than the market moves.
WITH lt AS (
  SELECT census_tract, lei, count(*) AS decided,
         100.0*count(*) FILTER (WHERE action_taken='3')/count(*) AS rate
  FROM marts.fct_application
  WHERE action_taken IN ('1','3') AND census_tract <> 'UNKNOWN'
  GROUP BY 1,2
  HAVING count(*) >= 30)
SELECT count(*) AS tracts,
       round(CAST(percentile_cont(0.25) WITHIN GROUP (ORDER BY spread) AS numeric), 1) AS p25,
       round(CAST(percentile_cont(0.50) WITHIN GROUP (ORDER BY spread) AS numeric), 1) AS median,
       round(CAST(percentile_cont(0.75) WITHIN GROUP (ORDER BY spread) AS numeric), 1) AS p75,
       round(CAST(max(spread) AS numeric), 1)                                          AS max_spread
FROM (SELECT census_tract, max(rate)-min(rate) AS spread
      FROM lt GROUP BY 1 HAVING count(*) >= 4) s;
