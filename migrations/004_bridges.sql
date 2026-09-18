-- =====================================================================
-- 004  Bridge tables
--
-- Race, ethnicity, denial reason and automated underwriting system are
-- published as numbered repeating columns, which is a first normal form
-- violation. Unpivoting them is not tidiness: derived_race collapses
-- anyone reporting two or more races into a single bucket, so without
-- these bridges a multi-race applicant disappears from every individual
-- race group. The bridges let each application count in every category
-- its applicants actually reported.
-- =====================================================================

-- Staging pass: one md5 computation, reused by all four bridges.
DROP TABLE IF EXISTS marts.stg_repeating CASCADE;
CREATE UNLOGGED TABLE marts.stg_repeating AS
SELECT md5(l::text) AS row_hash,
       row_number() OVER (PARTITION BY md5(l::text) ORDER BY l.lei, l.census_tract) AS dup_seq,
       l.activity_year::int AS activity_year,
       l.applicant_race_1, l.applicant_race_2, l.applicant_race_3, l.applicant_race_4, l.applicant_race_5,
       l.co_applicant_race_1, l.co_applicant_race_2, l.co_applicant_race_3, l.co_applicant_race_4, l.co_applicant_race_5,
       l.applicant_ethnicity_1, l.applicant_ethnicity_2, l.applicant_ethnicity_3, l.applicant_ethnicity_4, l.applicant_ethnicity_5,
       l.co_applicant_ethnicity_1, l.co_applicant_ethnicity_2, l.co_applicant_ethnicity_3, l.co_applicant_ethnicity_4, l.co_applicant_ethnicity_5,
       l.denial_reason_1, l.denial_reason_2, l.denial_reason_3, l.denial_reason_4,
       l.aus_1, l.aus_2, l.aus_3, l.aus_4, l.aus_5
FROM raw.raw_lar l;
CREATE INDEX ON marts.stg_repeating (row_hash, dup_seq);

-- Resolve the surrogate key once.
DROP TABLE IF EXISTS marts.stg_keys CASCADE;
CREATE UNLOGGED TABLE marts.stg_keys AS
SELECT s.row_hash, s.dup_seq, f.activity_year, f.application_sk
FROM marts.stg_repeating s
JOIN marts.fct_application f ON f.row_hash = s.row_hash AND f.dup_seq = s.dup_seq;
CREATE INDEX ON marts.stg_keys (row_hash, dup_seq);

-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS marts.br_application_race CASCADE;
CREATE TABLE marts.br_application_race AS
SELECT k.activity_year, k.application_sk, v.party, v.slot, v.race_code
FROM marts.stg_repeating s
JOIN marts.stg_keys k ON k.row_hash = s.row_hash AND k.dup_seq = s.dup_seq
CROSS JOIN LATERAL (VALUES
  ('applicant',1,s.applicant_race_1),('applicant',2,s.applicant_race_2),('applicant',3,s.applicant_race_3),
  ('applicant',4,s.applicant_race_4),('applicant',5,s.applicant_race_5),
  ('co_applicant',1,s.co_applicant_race_1),('co_applicant',2,s.co_applicant_race_2),('co_applicant',3,s.co_applicant_race_3),
  ('co_applicant',4,s.co_applicant_race_4),('co_applicant',5,s.co_applicant_race_5)
) AS v(party, slot, race_code)
WHERE v.race_code IS NOT NULL AND btrim(v.race_code) <> '';

DROP TABLE IF EXISTS marts.br_application_ethnicity CASCADE;
CREATE TABLE marts.br_application_ethnicity AS
SELECT k.activity_year, k.application_sk, v.party, v.slot, v.ethnicity_code
FROM marts.stg_repeating s
JOIN marts.stg_keys k ON k.row_hash = s.row_hash AND k.dup_seq = s.dup_seq
CROSS JOIN LATERAL (VALUES
  ('applicant',1,s.applicant_ethnicity_1),('applicant',2,s.applicant_ethnicity_2),('applicant',3,s.applicant_ethnicity_3),
  ('applicant',4,s.applicant_ethnicity_4),('applicant',5,s.applicant_ethnicity_5),
  ('co_applicant',1,s.co_applicant_ethnicity_1),('co_applicant',2,s.co_applicant_ethnicity_2),('co_applicant',3,s.co_applicant_ethnicity_3),
  ('co_applicant',4,s.co_applicant_ethnicity_4),('co_applicant',5,s.co_applicant_ethnicity_5)
) AS v(party, slot, ethnicity_code)
WHERE v.ethnicity_code IS NOT NULL AND btrim(v.ethnicity_code) <> '';

DROP TABLE IF EXISTS marts.br_denial_reason CASCADE;
CREATE TABLE marts.br_denial_reason AS
SELECT k.activity_year, k.application_sk, v.slot AS reason_ordinal, v.denial_reason_code
FROM marts.stg_repeating s
JOIN marts.stg_keys k ON k.row_hash = s.row_hash AND k.dup_seq = s.dup_seq
CROSS JOIN LATERAL (VALUES
  (1,s.denial_reason_1),(2,s.denial_reason_2),(3,s.denial_reason_3),(4,s.denial_reason_4)
) AS v(slot, denial_reason_code)
WHERE v.denial_reason_code IS NOT NULL AND btrim(v.denial_reason_code) <> ''
  AND v.denial_reason_code <> '10';   -- 10 means not applicable: no reason was given

DROP TABLE IF EXISTS marts.br_underwriting_system CASCADE;
CREATE TABLE marts.br_underwriting_system AS
SELECT k.activity_year, k.application_sk, v.slot AS aus_ordinal, v.aus_code
FROM marts.stg_repeating s
JOIN marts.stg_keys k ON k.row_hash = s.row_hash AND k.dup_seq = s.dup_seq
CROSS JOIN LATERAL (VALUES
  (1,s.aus_1),(2,s.aus_2),(3,s.aus_3),(4,s.aus_4),(5,s.aus_5)
) AS v(slot, aus_code)
WHERE v.aus_code IS NOT NULL AND btrim(v.aus_code) <> ''
  AND v.aus_code <> '6';              -- 6 means not applicable

DROP TABLE IF EXISTS marts.stg_repeating CASCADE;
