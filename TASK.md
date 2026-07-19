# KPI Analyst Trial Task

Data Engineer / KPI Analyst role, Lion Sales Funnel LLC.

## Context

A weekly audit compares a CRM export against a warehouse table and reports the match rate between them for a defined period. The expected match rate is about 96 percent. The current audit reports about 4 percent. Your job is to find out why, quantify the real number, and say plainly whether the fault is in the audit or in the data.

This is a self contained task. You provide your own PostgreSQL. Nothing connects to any external system.

## What you are given

- `system_a_crm_export.csv`, the CRM export, 500 rows. Load it as a table named `crm_export`.
- `system_b_warehouse.csv`, the warehouse table. Load it as a table named `warehouse`.
- `weekly_match_audit.sql`, the audit query as it runs today. It reports about 4 percent. Do not assume it is correct.

The audit period is 2026-07-01 through 2026-07-07 inclusive, defined in UTC.

## What to deliver

1. The true match rate for the period, as a number, with the SQL you used to get it.
2. A written finding that states whether the audit is wrong, the data is wrong, or both, and the specific cause of each issue you find. Order your reasoning.
3. For every issue you find, the evidence that proves it, not an assertion. Show the rows or the counts.
4. A corrected version of the audit query that returns the true rate.
5. A short note on how you validated your own answer before calling it done.

## How to submit

Put your SQL, your corrected query, and your written finding in a single repository or a single document. Include a short README with how to load the data and run your query. Reply to this email with the link.

## Envelope

This is a fixed scope task. Spend no more than a half day of working time on it. We are looking at how you reason and how you validate, not at volume. Confirm receipt and give your expected submission time when you start.

LION SALES FUNNEL LLC.
