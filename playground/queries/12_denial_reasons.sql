-- General analysis section 10: why applications fail.
-- Uses marts.v_denial_reason, the labelled view, restricted to reason_ordinal 1
-- so each denial is counted once under its primary reason. Restricted to
-- genuinely denied applications because 21,665 originated loans also carry a
-- denial reason, which is a filer error in the published data.
--
-- coalesce is not cosmetic. 31,821 denial-reason rows carry code 1111, HMDA's
-- "Exempt" value, and ref_code has no mapping for it, so the labelled view
-- returns NULL. Blanking it would hide 4,533 primary reasons. The gap belongs
-- in the ref_code seed; until it is fixed the code is named here.
SELECT coalesce(v.denial_reason, 'Exempt (code 1111, unmapped)') AS primary_reason,
       count(*)                                          AS denials,
       round(CAST(100.0*count(*) AS DECIMAL(24,8))
                  / CAST(sum(count(*)) OVER () AS DECIMAL(24,8)), 1) AS pct
FROM marts.v_denial_reason v
JOIN marts.fct_application f
  ON f.activity_year = v.activity_year AND f.application_sk = v.application_sk
WHERE v.reason_ordinal = 1 AND f.action_taken = '3'
GROUP BY 1 ORDER BY 2 DESC, 1;
