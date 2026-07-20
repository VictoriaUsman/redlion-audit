# Weekly Match Audit — Submission

This is my submission for the KPI Analyst trial task for Lion Sales Funnel LLC.

**The situation:** every week, a report checks how many customers in the CRM (the sales/contact
system) also show up in the warehouse (the records system), and prints out what percentage
matched. That report is supposed to say about 96%, but it's been printing about 4% instead.

**What I found:** the report itself had two bugs in it, and there's also one real, small gap
in the underlying data. Once the report is fixed, it correctly shows **96%**, matching what
was expected. The full write-up, in plain language with the evidence for each claim, is in
`FINDINGS.md`.

## What's in this folder

- `TASK.md` — the original assignment, unchanged.
- `FINDINGS.md` — my write-up: what the real match rate is, what was wrong and why, with the
  evidence for each claim.
- `corrected_audit.sql` — the fixed version of the report, ready to run.
- `system_a_crm_export.csv`, `system_b_warehouse.csv` — the original data provided for the
  task, untouched.

## How to check my work

You don't need to take my word for the 96% number — anyone with PostgreSQL installed can load
the same two data files and run the same fixed report themselves and see the same result.

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

That should print a match rate of 96.0%, out of 494 customers checked, with 474 matched and
20 not found.

See `FINDINGS.md` for the details: what exactly was wrong, how I found each issue, and the
evidence behind every number above.
