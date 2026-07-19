-- weekly_match_audit.sql
-- Reports the GHL-to-warehouse match rate for the audit period.
-- Expected ~96%. Currently reporting ~4%. Do not assume it is correct.
SELECT
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE w.patient_key IS NULL)
        / NULLIF(COUNT(*), 0)
    , 1) AS match_rate_pct
FROM crm_export c
LEFT JOIN warehouse w
    ON w.patient_key = c.contact_id
WHERE c.created_at >= '2026-07-01' AND c.created_at < '2026-07-08';
