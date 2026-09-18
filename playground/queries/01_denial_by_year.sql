-- Phase 08 finding 1: the market tightened, then partly recovered.
SELECT activity_year,
       count(*)                                                        AS decided,
       round(100.0*count(*) FILTER (WHERE action_taken='3')/count(*),2) AS denial_pct
FROM marts.fct_application
WHERE action_taken IN ('1','3')
GROUP BY 1
ORDER BY 1;
