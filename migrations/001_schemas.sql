-- =====================================================================
-- 001  Schemas and helper functions
-- Layering: raw (as received) -> ref (reference data) -> marts (modelled)
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS marts;

-- Move the as-received tables into the raw schema. They are never edited.
ALTER TABLE IF EXISTS public.raw_lar    SET SCHEMA raw;
ALTER TABLE IF EXISTS public.raw_ts     SET SCHEMA raw;
ALTER TABLE IF EXISTS public.raw_msamd  SET SCHEMA raw;
ALTER TABLE IF EXISTS public.raw_lender SET SCHEMA raw;
ALTER TABLE IF EXISTS public.ref_code            SET SCHEMA ref;
ALTER TABLE IF EXISTS public.ref_source_vintage  SET SCHEMA ref;

-- ---------------------------------------------------------------------
-- HMDA encodes "no value" three different ways in otherwise numeric
-- columns: the literal 'NA', the literal 'Exempt', and the sentinel
-- '1111'. Collapsing them to NULL is the only safe cast, but the reason
-- for the NULL is itself information, so ref.na_reason() preserves it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ref.to_num(v text)
RETURNS numeric LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN v IS NULL OR btrim(v) = '' THEN NULL
              WHEN btrim(v) IN ('NA','Exempt','1111','8888','9999') THEN NULL
              WHEN btrim(v) ~ '^-?[0-9]+(\.[0-9]+)?$' THEN btrim(v)::numeric
              ELSE NULL END
$$;

CREATE OR REPLACE FUNCTION ref.na_reason(v text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN v IS NULL OR btrim(v) = '' THEN 'blank'
              WHEN btrim(v) = 'NA'            THEN 'not_applicable'
              WHEN btrim(v) = 'Exempt'        THEN 'exempt_filer'
              WHEN btrim(v) = '1111'          THEN 'exempt_sentinel'
              WHEN btrim(v) = '8888'          THEN 'not_applicable_sentinel'
              WHEN btrim(v) = '9999'          THEN 'no_co_applicant'
              WHEN btrim(v) ~ '^-?[0-9]+(\.[0-9]+)?$' THEN NULL
              ELSE 'unparseable' END
$$;

-- The county FIPS code is the first five characters of an 11-digit census
-- tract code, so a missing county_code is recoverable whenever the tract
-- is present. 181 tract-years in this data need that repair.
CREATE OR REPLACE FUNCTION ref.repair_county(county text, tract text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE WHEN county IS NOT NULL AND county <> 'NA' AND btrim(county) <> '' THEN county
              WHEN tract IS NOT NULL AND tract <> 'NA' AND length(btrim(tract)) = 11 THEN left(btrim(tract),5)
              ELSE NULL END
$$;
