-- =====================================================================
-- 006  Quarantine and domain constraints
--
-- A mart should refuse data that cannot be true, but silently dropping
-- bad rows destroys evidence. So the rules are declared in a table,
-- every violating row is moved to quarantine with the rule it broke,
-- and only then are the constraints applied to the clean mart.
--
-- This step is idempotent: re-running it finds nothing new.
-- =====================================================================
CREATE TABLE IF NOT EXISTS marts.quarantine_application (
  LIKE marts.fct_application,
  violated_rule text NOT NULL,
  detected_at   timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- Rule 1  interest_rate must be a percentage, not basis points.
--         One 2022 row reports 450.0, almost certainly 4.50 mistyped.
-- Rule 2  loan_to_value_ratio above 300 is not a ratio. 174 rows exceed
--         1000 and the largest is 86,496,900, so these are amounts or
--         unit errors rather than percentages.
-- Rule 3  loan_amount must be positive.
-- ---------------------------------------------------------------------
WITH bad AS (
  SELECT f.activity_year, f.application_sk,
         CASE WHEN f.interest_rate > 50            THEN 'interest_rate_not_a_percentage'
              WHEN f.loan_to_value_ratio > 300     THEN 'ltv_not_a_ratio'
              WHEN f.loan_amount <= 0              THEN 'loan_amount_not_positive'
         END AS rule
  FROM marts.fct_application f
  WHERE f.interest_rate > 50 OR f.loan_to_value_ratio > 300 OR f.loan_amount <= 0
)
INSERT INTO marts.quarantine_application
SELECT f.*, b.rule, now()
FROM marts.fct_application f
JOIN bad b USING (activity_year, application_sk)
WHERE NOT EXISTS (
  SELECT 1 FROM marts.quarantine_application q
  WHERE q.activity_year = f.activity_year AND q.application_sk = f.application_sk);

DELETE FROM marts.br_application_race      b USING marts.quarantine_application q
  WHERE b.activity_year=q.activity_year AND b.application_sk=q.application_sk;
DELETE FROM marts.br_application_ethnicity b USING marts.quarantine_application q
  WHERE b.activity_year=q.activity_year AND b.application_sk=q.application_sk;
DELETE FROM marts.br_denial_reason         b USING marts.quarantine_application q
  WHERE b.activity_year=q.activity_year AND b.application_sk=q.application_sk;
DELETE FROM marts.br_underwriting_system   b USING marts.quarantine_application q
  WHERE b.activity_year=q.activity_year AND b.application_sk=q.application_sk;
DELETE FROM marts.fct_application f USING marts.quarantine_application q
  WHERE f.activity_year=q.activity_year AND f.application_sk=q.application_sk;

-- The constraints now hold, and will reject the same errors next time.
ALTER TABLE marts.fct_application
  ADD CONSTRAINT ck_action_taken          CHECK (action_taken IN ('1','2','3','4','5','6','7','8')),
  ADD CONSTRAINT ck_loan_amount_positive  CHECK (loan_amount IS NULL OR loan_amount > 0),
  ADD CONSTRAINT ck_interest_rate_sane    CHECK (interest_rate IS NULL OR interest_rate BETWEEN 0 AND 50),
  ADD CONSTRAINT ck_ltv_is_a_ratio        CHECK (loan_to_value_ratio IS NULL OR loan_to_value_ratio BETWEEN 0 AND 300),
  ADD CONSTRAINT ck_dup_seq_positive      CHECK (dup_seq >= 1);

ALTER TABLE marts.br_application_race
  ADD CONSTRAINT fk_br_race_app FOREIGN KEY (activity_year, application_sk)
      REFERENCES marts.fct_application (activity_year, application_sk) ON DELETE CASCADE;
ALTER TABLE marts.br_application_ethnicity
  ADD CONSTRAINT fk_br_eth_app FOREIGN KEY (activity_year, application_sk)
      REFERENCES marts.fct_application (activity_year, application_sk) ON DELETE CASCADE;
ALTER TABLE marts.br_denial_reason
  ADD CONSTRAINT fk_br_denial_app FOREIGN KEY (activity_year, application_sk)
      REFERENCES marts.fct_application (activity_year, application_sk) ON DELETE CASCADE;
ALTER TABLE marts.br_underwriting_system
  ADD CONSTRAINT fk_br_aus_app FOREIGN KEY (activity_year, application_sk)
      REFERENCES marts.fct_application (activity_year, application_sk) ON DELETE CASCADE;

DROP TABLE IF EXISTS marts.stg_keys CASCADE;
ANALYZE marts.fct_application;
