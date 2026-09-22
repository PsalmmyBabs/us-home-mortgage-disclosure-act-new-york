-- General analysis section 7: where the lending happens.
-- msa_md 99999 is HMDA's code for a property outside any metropolitan area, so
-- it has no name in dim_msa and is labelled here rather than left blank.
-- NULLS LAST is not decoration: PostgreSQL sorts NULLs first on DESC and DuckDB
-- sorts them last, so without it the two engines return different top tens.
SELECT CASE WHEN coalesce(m.msa_md_name, '') = ''
            THEN 'Outside any metropolitan area' ELSE m.msa_md_name END AS area,
       count(*)                                          AS applications,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct_of_state,
       round(CAST(100.0*count(*) FILTER (WHERE f.action_taken IN ('1','2')) AS DECIMAL(24,8))
                  / CAST(count(*) AS DECIMAL(24,8)), 1)             AS approval_rate,
       round(CAST(percentile_cont(0.5) WITHIN GROUP (
              ORDER BY CASE WHEN f.action_taken IN ('1','2') THEN f.loan_amount END)
             AS numeric))                                AS median_approved,
       round(CAST(coalesce(sum(f.loan_amount) FILTER (WHERE f.action_taken = '1'), 0) AS DECIMAL(24,4))
             / 1000000000, 2)                             AS disbursed_bn
FROM marts.fct_application f
LEFT JOIN marts.dim_msa m
       ON m.activity_year = f.activity_year AND m.msa_md = f.msa_md
WHERE f.action_taken <> '6'
GROUP BY 1
ORDER BY 2 DESC NULLS LAST, 1
LIMIT 10;
