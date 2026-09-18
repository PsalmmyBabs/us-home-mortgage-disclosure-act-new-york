-- Phase 06 section 1: nothing was deleted.
SELECT (SELECT count(*) FROM marts.fct_application)        AS modelled,
       (SELECT count(*) FROM marts.quarantine_application) AS quarantined,
       (SELECT count(*) FROM marts.fct_application)
     + (SELECT count(*) FROM marts.quarantine_application) AS total_published;
