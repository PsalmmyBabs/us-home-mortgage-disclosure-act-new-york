-- =====================================================================
-- 005  Keys, constraints and indexes
-- Constraints are declared after the bulk load so the load is not
-- validated row by row, but they ARE declared: an undeclared model is
-- an unverified one.
-- =====================================================================

-- Primary keys. A partitioned table's primary key must contain the
-- partition key, so activity_year leads.
ALTER TABLE marts.fct_application       ADD PRIMARY KEY (activity_year, application_sk);
ALTER TABLE marts.br_application_race   ADD PRIMARY KEY (activity_year, application_sk, party, slot);
ALTER TABLE marts.br_application_ethnicity ADD PRIMARY KEY (activity_year, application_sk, party, slot);
ALTER TABLE marts.br_denial_reason      ADD PRIMARY KEY (activity_year, application_sk, reason_ordinal);
ALTER TABLE marts.br_underwriting_system ADD PRIMARY KEY (activity_year, application_sk, aus_ordinal);

-- The deterministic business key is unique in its own right.
ALTER TABLE marts.fct_application ADD CONSTRAINT uq_fct_row_occurrence UNIQUE (activity_year, row_hash, dup_seq);

-- Referential integrity to every dimension.
ALTER TABLE marts.fct_application
  ADD CONSTRAINT fk_fct_date        FOREIGN KEY (activity_year) REFERENCES marts.dim_date(activity_year),
  ADD CONSTRAINT fk_fct_institution FOREIGN KEY (activity_year, lei) REFERENCES marts.dim_institution(activity_year, lei),
  ADD CONSTRAINT fk_fct_tract       FOREIGN KEY (activity_year, census_tract) REFERENCES marts.dim_tract(activity_year, census_tract),
  ADD CONSTRAINT fk_fct_county      FOREIGN KEY (activity_year, county_code)  REFERENCES marts.dim_county(activity_year, county_code),
  ADD CONSTRAINT fk_fct_msa         FOREIGN KEY (activity_year, msa_md)       REFERENCES marts.dim_msa(activity_year, msa_md),
  ADD CONSTRAINT fk_fct_product     FOREIGN KEY (loan_product_sk)      REFERENCES marts.dim_loan_product(loan_product_sk),
  ADD CONSTRAINT fk_fct_dwelling    FOREIGN KEY (dwelling_sk)          REFERENCES marts.dim_dwelling(dwelling_sk),
  ADD CONSTRAINT fk_fct_applicant   FOREIGN KEY (applicant_profile_sk) REFERENCES marts.dim_applicant_profile(applicant_profile_sk);

ALTER TABLE marts.dim_tract
  ADD CONSTRAINT fk_tract_county FOREIGN KEY (activity_year, county_code) REFERENCES marts.dim_county(activity_year, county_code);
ALTER TABLE marts.dim_county
  ADD CONSTRAINT fk_county_msa   FOREIGN KEY (activity_year, msa_md) REFERENCES marts.dim_msa(activity_year, msa_md);

-- Domain checks: values that must be true by definition.
ALTER TABLE marts.fct_application
  ADD CONSTRAINT ck_action_taken CHECK (action_taken IN ('1','2','3','4','5','6','7','8')),
  ADD CONSTRAINT ck_loan_amount_positive CHECK (loan_amount IS NULL OR loan_amount > 0),
  ADD CONSTRAINT ck_interest_rate_sane   CHECK (interest_rate IS NULL OR (interest_rate >= 0 AND interest_rate <= 50)),
  ADD CONSTRAINT ck_dup_seq_positive     CHECK (dup_seq >= 1);

-- Indexes chosen from the predicates the analysis actually uses.
-- Nearly every fairness query filters to decided applications, so that
-- becomes a partial index rather than a full one.
CREATE INDEX idx_fct_decided        ON marts.fct_application (activity_year, applicant_profile_sk)
  WHERE action_taken IN ('1','3');
CREATE INDEX idx_fct_lender_tract   ON marts.fct_application (lei, census_tract);
CREATE INDEX idx_fct_tract          ON marts.fct_application (activity_year, census_tract);
CREATE INDEX idx_fct_product        ON marts.fct_application (loan_product_sk);
CREATE INDEX idx_fct_action         ON marts.fct_application (action_taken);

-- Bridge lookups always start from the fact.
CREATE INDEX idx_br_race_app        ON marts.br_application_race (activity_year, application_sk);
CREATE INDEX idx_br_race_code       ON marts.br_application_race (race_code) WHERE party = 'applicant';
CREATE INDEX idx_br_denial_app      ON marts.br_denial_reason (activity_year, application_sk);
CREATE INDEX idx_br_aus_app         ON marts.br_underwriting_system (activity_year, application_sk);

-- Dimension lookups by label.
CREATE INDEX idx_dim_inst_name      ON marts.dim_institution (institution_name);
CREATE INDEX idx_dim_inst_holder    ON marts.dim_institution (top_holder_rssd);
CREATE INDEX idx_dim_tract_minority ON marts.dim_tract (activity_year, minority_population_pct);

ANALYZE marts.fct_application;
ANALYZE marts.br_application_race;
ANALYZE marts.br_denial_reason;
ANALYZE marts.br_underwriting_system;
ANALYZE marts.dim_institution;
ANALYZE marts.dim_tract;
