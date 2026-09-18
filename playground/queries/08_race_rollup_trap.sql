-- Phase 06 section 4.1: HMDA race codes are hierarchical, so subcategories
-- must be rolled up to their parent before counting distinct races.
-- Written with left(...) rather than a regex on purpose: see phase 10.
SELECT
  (SELECT count(*) FROM (
     SELECT activity_year, application_sk FROM marts.br_application_race
     WHERE party='applicant'
     GROUP BY 1,2 HAVING count(DISTINCT race_code) > 1) z)            AS naive_count,
  (SELECT count(*) FROM (
     SELECT activity_year, application_sk FROM marts.br_application_race
     WHERE party='applicant' AND left(race_code,1) IN ('1','2','3','4','5')
     GROUP BY 1,2 HAVING count(DISTINCT left(race_code,1)) > 1) z)    AS rolled_up_count;
