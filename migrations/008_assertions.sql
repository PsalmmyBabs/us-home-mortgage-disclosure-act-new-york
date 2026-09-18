-- =====================================================================
-- 008  Quality assertions with severity
--
-- Two kinds of problem need separating. A BUILD error means the pipeline
-- is wrong and must fail. A SOURCE defect means the regulator's filers
-- submitted something inconsistent: real, worth quantifying, and not
-- something this repository can fix. Those get a documented tolerance so
-- CI stays meaningful instead of being permanently red.
-- =====================================================================
DROP TABLE IF EXISTS ref.assertion_catalog CASCADE;
CREATE TABLE ref.assertion_catalog (
  assertion   text PRIMARY KEY,
  severity    text NOT NULL CHECK (severity IN ('build_error','source_defect')),
  tolerance   numeric,             -- max acceptable share of rows, source defects only
  description text NOT NULL
);
INSERT INTO ref.assertion_catalog VALUES
 ('fact_does_not_reconcile_to_raw','build_error',NULL,'Fact plus quarantine must equal the raw row count'),
 ('row_hash_dup_seq_not_unique','build_error',NULL,'The deterministic business key must be unique'),
 ('unmapped_code','build_error',NULL,'Every code in the fact must resolve to a label in ref_code'),
 ('orphan_tract','build_error',NULL,'Every fact row must join to its tract-year'),
 ('tract_attributes_vary_within_year','build_error',NULL,'dim_tract grain must be one row per tract-year'),
 ('year_missing_from_fact','build_error',NULL,'Every year in dim_date must appear in the fact'),
 ('denial_reason_on_non_denial','source_defect',0.02,
  'Filers report a denial reason where action taken is not a denial. Stable at 1.3 to 1.6 per cent of every year, concentrated in 167 institutions, 21,665 of them on ORIGINATED loans. A filer system defect, reported not fixed.'),
 ('denied_without_reason','source_defect',0.01,
  'A denied application with no reason recorded');

CREATE OR REPLACE VIEW marts.assert_results AS
WITH checks AS (
  SELECT 'fact_does_not_reconcile_to_raw' AS assertion,
         CASE WHEN (SELECT count(*) FROM raw.raw_lar)
                <> (SELECT count(*) FROM marts.fct_application)
                 + (SELECT count(*) FROM marts.quarantine_application) THEN 1 ELSE 0 END AS failing_rows
  UNION ALL
  SELECT 'row_hash_dup_seq_not_unique',
         (SELECT count(*) FROM (SELECT 1 FROM marts.fct_application
            GROUP BY activity_year, row_hash, dup_seq HAVING count(*)>1) z)
  UNION ALL
  SELECT 'unmapped_code',
         (SELECT count(*) FROM marts.fct_application f
          WHERE NOT EXISTS (SELECT 1 FROM ref.ref_code r
                            WHERE r.code_field='action_taken' AND r.code_value=f.action_taken))
  UNION ALL
  SELECT 'orphan_tract',
         (SELECT count(*) FROM marts.fct_application f
          WHERE NOT EXISTS (SELECT 1 FROM marts.dim_tract t
                            WHERE t.activity_year=f.activity_year AND t.census_tract=f.census_tract))
  UNION ALL
  SELECT 'tract_attributes_vary_within_year',
         (SELECT count(*) FROM (SELECT 1 FROM marts.dim_tract
            GROUP BY activity_year, census_tract HAVING count(*)>1) z)
  UNION ALL
  SELECT 'year_missing_from_fact',
         (SELECT count(*) FROM marts.dim_date d
          WHERE NOT EXISTS (SELECT 1 FROM marts.fct_application f WHERE f.activity_year=d.activity_year))
  UNION ALL
  SELECT 'denial_reason_on_non_denial',
         (SELECT count(DISTINCT (f.activity_year, f.application_sk))
          FROM marts.fct_application f
          JOIN marts.br_denial_reason b ON b.activity_year=f.activity_year AND b.application_sk=f.application_sk
          WHERE f.action_taken NOT IN ('3','7'))
  UNION ALL
  SELECT 'denied_without_reason',
         (SELECT count(*) FROM marts.fct_application f
          WHERE f.action_taken='3'
            AND NOT EXISTS (SELECT 1 FROM marts.br_denial_reason b
                            WHERE b.activity_year=f.activity_year AND b.application_sk=f.application_sk))
)
SELECT c.assertion,
       a.severity,
       c.failing_rows,
       round(100.0*c.failing_rows/(SELECT count(*) FROM marts.fct_application),3) AS pct_of_fact,
       a.tolerance,
       CASE WHEN c.failing_rows = 0 THEN 'pass'
            WHEN a.severity = 'build_error' THEN 'FAIL'
            WHEN 1.0*c.failing_rows/(SELECT count(*) FROM marts.fct_application) <= a.tolerance THEN 'known_issue_within_tolerance'
            ELSE 'FAIL' END AS status,
       a.description
FROM checks c JOIN ref.assertion_catalog a USING (assertion);

-- CI gate: returns rows only when the build is actually broken.
DROP VIEW IF EXISTS marts.assert_failures;
CREATE VIEW marts.assert_failures AS
SELECT * FROM marts.assert_results WHERE status = 'FAIL';
