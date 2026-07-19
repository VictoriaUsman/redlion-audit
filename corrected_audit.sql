-- corrected_audit.sql
-- Corrected GHL-to-warehouse match rate for the audit period 2026-07-01..2026-07-07 UTC inclusive.
-- True rate: 96.0% (474/494). See FINDINGS.md for how this was derived.

SELECT
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE w.patient_key IS NOT NULL)
        / NULLIF(COUNT(*), 0)
    , 1) AS match_rate_pct,
    COUNT(*) AS total_in_period,
    COUNT(*) FILTER (WHERE w.patient_key IS NOT NULL) AS matched,
    COUNT(*) FILTER (WHERE w.patient_key IS NULL) AS unmatched
FROM crm_export c
LEFT JOIN warehouse w
    ON w.patient_key::bigint = c.contact_id::bigint
WHERE c.created_at::timestamptz >= '2026-07-01T00:00:00+00'
  AND c.created_at::timestamptz <  '2026-07-08T00:00:00+00';
