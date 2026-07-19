# Weekly Match Audit — Findings

## True match rate

**96.0%** (474 matched / 494 in-period CRM contacts), for the audit period
2026-07-01T00:00:00Z through 2026-07-07T23:59:59Z (i.e. `created_at >= 2026-07-01` and
`< 2026-07-08`, UTC).

This matches the ~96% expectation stated in the brief.

## Corrected audit query

```sql
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

--  match_rate_pct | total_in_period | matched | unmatched
--  96.0           | 494             | 474     | 20
```
<img width="1496" height="1052" alt="725166C9-706D-4D13-A70B-9F7BDD9ADA9E" src="https://github.com/user-attachments/assets/429b2cfb-623e-4852-b178-9cb70a30a248" />


## Verdict

Both the audit and the data are wrong, in that order of impact:

1. **The audit query has an inverted filter** (the dominant cause of the 4% vs 96% gap).
2. **The audit query does a type/format-mismatched join** (a secondary, smaller cause).
3. **The warehouse is genuinely missing 20 records** (a real data gap, not a query bug — this
   is the only reason the true rate is 96% and not 100%).

## Issue 1 — Inverted match filter (query bug, the main cause)

`weekly_match_audit.sql` computes:

```sql
COUNT(*) FILTER (WHERE w.patient_key IS NULL) / COUNT(*)
```

`w.patient_key IS NULL` after a `LEFT JOIN` identifies **non-matches** (CRM rows with no
warehouse row). The query labels this `match_rate_pct`, so it reports the *miss* rate as if
it were the *match* rate. It should filter on `IS NOT NULL`.

**Evidence:** re-running the query as originally written against the loaded data:

```sql
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE w.patient_key IS NULL) / NULLIF(COUNT(*), 0), 1)
FROM crm_export c
LEFT JOIN warehouse w ON w.patient_key = c.contact_id
WHERE c.created_at >= '2026-07-01' AND c.created_at < '2026-07-08';
-- match_rate_pct: 10.1
```

Simply flipping `IS NULL` to `IS NOT NULL` on the exact same join, same period:

```sql
SELECT
    COUNT(*) AS total_in_period,
    COUNT(*) FILTER (WHERE w.patient_key IS NOT NULL) AS naive_matches,
    COUNT(*) FILTER (WHERE w.patient_key IS NULL)     AS naive_non_matches
FROM crm_export c
LEFT JOIN warehouse w ON w.patient_key = c.contact_id
WHERE c.created_at >= '2026-07-01' AND c.created_at < '2026-07-08';
--  total_in_period | naive_matches | naive_non_matches
--  494             | 444           | 50
```

That alone moves the reported number from 10.1% to 89.9% — most of the gap between "4%" and
"96%" is this one line.

## Issue 2 — Key format mismatch breaks the join (query bug, secondary cause)

`warehouse.patient_key` is inconsistently zero-padded: most rows are a 5-digit string
(`10249`), but 30 rows are stored zero-padded to 8 digits (`00010249`). `crm_export.contact_id`
is never padded. The join `w.patient_key = c.contact_id` does exact string equality, so these
30 warehouse rows can never match their corresponding CRM row even though they represent the
same patient.

**Evidence** — the 30 zero-padded warehouse rows:

```
patient_key | collections | visit_date
00010033    | 609         | 2026-07-06
00010046    | 169         | 2026-07-05
00010063    | 553         | 2026-07-01
00010089    | 432         | 2026-07-06
00010098    | 894         | 2026-07-01
00010108    | 759         | 2026-07-04
00010119    | 390         | 2026-07-01
00010149    | 876         | 2026-07-03
00010192    | 121         | 2026-07-04
00010197    | 747         | 2026-07-02
00010205    | 504         | 2026-07-03
00010236    | 346         | 2026-07-06
00010248    | 273         | 2026-07-04
00010249    | 770         | 2026-07-05
00010286    | 94          | 2026-07-07
00010291    | 221         | 2026-07-05
00010299    | 256         | 2026-07-06
00010305    | 391         | 2026-07-05
00010307    | 810         | 2026-07-07
00010333    | 319         | 2026-07-05
00010349    | 436         | 2026-07-07
00010359    | 249         | 2026-07-03
00010375    | 751         | 2026-07-05
00010395    | 259         | 2026-07-04
00010415    | 876         | 2026-07-03
00010430    | 503         | 2026-07-04
00010455    | 701         | 2026-07-01
00010460    | 895         | 2026-07-06
00010472    | 128         | 2026-07-04
00010481    | 629         | 2026-07-06
```

Normalizing both sides of the join to `bigint` (`w.patient_key::bigint = c.contact_id::bigint`)
recovers all 30 of these as matches, with no false positives — verified against the CRM table:
every one of the 500 `contact_id` values and all 480 `patient_key` values are purely numeric
(`^[0-9]+$`), so the cast is safe and lossless in both directions, and there are no duplicate
`contact_id` or `patient_key` values that could fan the join out.

This raises naive_matches from 444 to 474 (out of 494 in-period rows): 96.0%.

### A secondary, non-scoring observation on the same query

The period filter compares `created_at` as a bare string/timestamp literal
(`created_at >= '2026-07-01'`). Six CRM rows carry a `+08:00` offset instead of `+00:00`
(`2026-06-30T23:30:00+08:00`, contact_ids 10001–10006). In this dataset those six rows are
correctly excluded either way — `2026-06-30T23:30:00+08:00` is `2026-06-30T15:30:00Z`, genuinely
before the period start, and happens to sort before `'2026-07-01'` as plain text too. So it does
not change the count here. It's still worth casting explicitly to `timestamptz` and comparing
against explicit UTC bounds (as `corrected_audit.sql` does), because a differently-offset
timestamp (e.g. a large positive offset that crosses a date boundary the other way) would give
a wrong answer under naive string/local comparison but a correct one under an explicit UTC cast.
Flagging this as defensive hardening, not as a cause of the reported 4%.

## Issue 3 — 20 CRM contacts have no warehouse row at all (data gap, not a query bug)

After correcting both query issues above, 20 of the 494 in-period CRM contacts still have no
matching warehouse row, under any key normalization (checked by casting both sides to `bigint`,
which is padding-width-agnostic). These are genuinely absent from `warehouse`, not a formatting
artifact.

**Evidence** — the 20 CRM rows with no corresponding warehouse record, under any key format:

```
contact_id | email                   | created_at                | source
10018      | patient18@example.com   | 2026-07-05T10:00:00+00:00 | google
10043      | patient43@example.com   | 2026-07-02T10:00:00+00:00 | meta
10136      | patient136@example.com  | 2026-07-04T10:00:00+00:00 | direct
10157      | patient157@example.com  | 2026-07-04T10:00:00+00:00 | referral
10179      | patient179@example.com  | 2026-07-05T10:00:00+00:00 | meta
10183      | patient183@example.com  | 2026-07-02T10:00:00+00:00 | google
10214      | patient214@example.com  | 2026-07-05T10:00:00+00:00 | direct
10218      | patient218@example.com  | 2026-07-02T10:00:00+00:00 | meta
10221      | patient221@example.com  | 2026-07-05T10:00:00+00:00 | referral
10238      | patient238@example.com  | 2026-07-01T10:00:00+00:00 | referral
10274      | patient274@example.com  | 2026-07-02T10:00:00+00:00 | referral
10279      | patient279@example.com  | 2026-07-07T10:00:00+00:00 | direct
10280      | patient280@example.com  | 2026-07-01T10:00:00+00:00 | google
10300      | patient300@example.com  | 2026-07-07T10:00:00+00:00 | google
10380      | patient380@example.com  | 2026-07-03T10:00:00+00:00 | referral
10431      | patient431@example.com  | 2026-07-05T10:00:00+00:00 | google
10454      | patient454@example.com  | 2026-07-07T10:00:00+00:00 | referral
10466      | patient466@example.com  | 2026-07-05T10:00:00+00:00 | referral
10488      | patient488@example.com  | 2026-07-06T10:00:00+00:00 | referral
10490      | patient490@example.com  | 2026-07-01T10:00:00+00:00 | direct
```

These 20 records are what keep the true rate at 96.0% rather than 100%. Whether this is
acceptable (e.g. warehouse ingestion lag for very recent contacts) or a real problem is a
question for whoever owns the warehouse ETL — the SQL alone can't determine cause, only surface
the gap.

## Reasoning order

1. Started from the stated fact: audit reports ~4%, expected ~96%. A ~92-point gap between a
   reported rate and its complement (4% vs 96%, which sum to 100%) is the signature of an
   inverted boolean condition, not a data-quality issue — data problems degrade a rate, they
   don't flip it to its complement. That was the first thing checked, and it was confirmed by
   re-running the query as-written and then only flipping `IS NULL`→`IS NOT NULL`.
2. With the filter fixed, the rate was 89.9%, not yet 96%, so a real secondary issue remained.
   Inspected the join keys directly for format mismatches (a classic cause of "silent" join
   misses) and found the zero-padded `patient_key` rows.
3. After normalizing key format, 20 rows still didn't match under any normalization. At that
   point the only remaining explanation is a true data gap, confirmed by checking that these
   20 `contact_id`s exist in `crm_export` but nowhere in `warehouse` regardless of formatting.

## Validation

- Recomputed the same figures two independent ways: (a) a single query with `bigint`-normalized
  join + explicit `timestamptz` period bounds (`corrected_audit.sql`), and (b) built up
  incrementally issue-by-issue (naive filter flip → 89.9%, then padding fix → 96.0%) to confirm
  the final number decomposes into exactly the two query fixes plus the residual gap, with no
  other unexplained movement.
- Checked join-safety preconditions before trusting the `bigint` cast: confirmed with
  `WHERE contact_id !~ '^[0-9]+$'` / `WHERE patient_key !~ '^[0-9]+$'` that both columns are
  100% numeric (zero rows returned), and confirmed no duplicate `contact_id` or `patient_key`
  values exist (`GROUP BY ... HAVING count(*) > 1`, zero rows both), so the join can't silently
  fan out and inflate either the matched or unmatched count.
- Cross-checked the period boundary two ways (plain string comparison vs. explicit
  `::timestamptz` cast against UTC bounds) and confirmed both give the same 494-row denominator,
  so the `+08:00`-offset rows are handled correctly either way in this dataset (see the note
  under Issue 2).
- Traced the final 20 unmatched rows back to source: confirmed each exists in `crm_export`,
  confirmed none exists in `warehouse` under exact match, zero-padded match, or numeric-cast
  match — ruling out a fourth formatting variant before calling it a genuine gap.
