-- Phase 08 section 1: why the denominator has to be decided applications only.
SELECT f.action_taken, c.label,
       count(*)                                              AS rows,
       round(100.0*count(*)/sum(count(*)) OVER (), 1)         AS pct
FROM marts.fct_application f
JOIN ref.ref_code c ON c.code_field='action_taken' AND c.code_value=f.action_taken
GROUP BY 1,2
ORDER BY 3 DESC;
