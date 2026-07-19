# Weekly Match Audit — Submission

KPI Analyst trial task (Lion Sales Funnel LLC): find why the weekly CRM-vs-warehouse match
audit reports ~4% against an expected ~96%, quantify the true rate, and correct the query.
Full task brief: `TASK.md`.

## Files

- `TASK.md` — original task brief, as provided.
- `FINDINGS.md` — the written finding: corrected SQL query, true match rate, root causes in order, evidence for each.
- `corrected_audit.sql` — the corrected query as a standalone runnable file, returns the true match rate.
- `system_a_crm_export.csv`, `system_b_warehouse.csv` — original data, unmodified, needed by the load steps below.

## How to load and run

Requires a local PostgreSQL (tested on Postgres 16).

```bash
createdb kpi_trial

psql -d kpi_trial <<'SQL'
CREATE TABLE crm_export (
    contact_id  text,
    email       text,
    created_at  text,
    source      text
);
CREATE TABLE warehouse (
    patient_key text,
    collections numeric,
    visit_date  date
);
SQL

psql -d kpi_trial -c "\copy crm_export FROM 'system_a_crm_export.csv' WITH (FORMAT csv, HEADER true)"
psql -d kpi_trial -c "\copy warehouse FROM 'system_b_warehouse.csv' WITH (FORMAT csv, HEADER true)"

psql -d kpi_trial -f corrected_audit.sql
```

Expected output: `match_rate_pct = 96.0`, `total_in_period = 494`, `matched = 474`,
`unmatched = 20`.

Note both key columns are loaded as `text`, not `integer`/`bigint`. That's deliberate: it
preserves the zero-padding in `warehouse.patient_key` exactly as it exists in the source data,
which is what exposed the format-mismatch issue documented in `FINDINGS.md`. The corrected
query normalizes with an explicit `::bigint` cast at join time rather than at load time.

See `FINDINGS.md` for the full analysis, evidence, and validation notes.
