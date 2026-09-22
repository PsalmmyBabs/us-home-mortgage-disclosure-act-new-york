-- Phase 08 finding 9: denial is not the only channel.
SELECT i.institution_name,
       count(*)                                                          AS applications,
       round(100.0*count(*) FILTER (WHERE f.action_taken='5')/count(*),1) AS closed_incomplete_pct
FROM marts.fct_application f
JOIN marts.dim_institution i ON i.activity_year = f.activity_year AND i.lei = f.lei
GROUP BY 1
HAVING count(*) >= 20000
ORDER BY 3 DESC;
