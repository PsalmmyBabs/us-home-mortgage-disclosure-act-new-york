-- =====================================================================
--  000b  Philadelphia Fed HMDA Lender File (the "Avery file")
--
--  The Fed publishes this as a spreadsheet covering 1990 to 2025. It has
--  been converted to CSV and filtered to the four years this project
--  uses, so the load needs nothing but psql. All columns are text; the
--  casting happens in 002_dimensions.sql like every other source.
--
--  Source: philadelphiafed.org/surveys-and-data/consumer-finance-data
--          /home-mortgage-disclosure-act-lender-file
--  Suggested citation: Federal Reserve Bank of Philadelphia,
--          HMDA Lender File (Avery File).
--
--  Load it with:
--      \copy raw.raw_lender FROM 'seed/lender_file_2022_2025.csv' WITH (FORMAT csv, HEADER true)
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS raw;
DROP TABLE IF EXISTS raw.raw_lender CASCADE;
CREATE TABLE raw.raw_lender (
  "year" text,
  "lei" text,
  "taxid" text,
  "code" text,
  "namet" text,
  "placet" text,
  "statet" text,
  "code17" text,
  "hmprid" text,
  "seqins" text,
  "exempt18" text,
  "type" text,
  "rssd" text,
  "namer" text,
  "forer" text,
  "chartr" text,
  "placer" text,
  "stater" text,
  "countyr" text,
  "taxidr" text,
  "leir" text,
  "rssdp" text,
  "namep" text,
  "rssdhh" text,
  "namehh" text,
  "entity" text,
  "name" text,
  "fore" text,
  "place" text,
  "state" text,
  "county" text,
  "insure" text,
  "minbnk" text,
  "cert" text,
  "occ" text,
  "thrift" text,
  "ncua" text,
  "assets" text,
  "assetl" text,
  "cradate" text,
  "crarate" text,
  "crameth" text,
  "fhlb" text,
  "fhlbid" text,
  "org" text,
  "nameor" text,
  "foreor" text,
  "charor" text,
  "assorg" text,
  "real14" text,
  "lar" text,
  "larsnap" text,
  "purc" text,
  "purcd" text,
  "appl" text,
  "appld" text,
  "applm" text,
  "appldm" text,
  "orig" text,
  "origd" text,
  "origm" text,
  "origdm" text,
  "appclo" text,
  "appclod" text,
  "appclom" text,
  "appclodm" text,
  "oriclo" text,
  "oriclod" text,
  "oriclom" text,
  "oriclodm" text,
  "entfut" text,
  "orgfut" text,
  "ginnie" text
);
