# Weekly Match Audit Findings

## Bottom line

The true match rate is **96.0%** (474 matched out of 494 CRM contacts in the audit period,
2026-07-01 through 2026-07-07 UTC inclusive). That lines up with what you told me to expect.

Short version of what I found: the audit query itself had two bugs, and there's also one real
gap in the underlying data. I'll walk through each one, in the order I found them, with the
evidence behind every number.

**One thing I want to flag up front, because I'd rather you hear it from me than notice it
yourself:** the brief describes the audit as "currently reporting about 4 percent." When I ran
the original `weekly_match_audit.sql`, unmodified, against the data you gave me, it actually
came back at **10.1%**, not ~4%.

<img width="1492" height="530" alt="0580F87B-BF69-48B6-86A3-FF4285A822C6" src="https://github.com/user-attachments/assets/8d7ff19e-993f-4295-9367-017ed528a8de" />

I don't think that changes the diagnosis. I'm reading "about 4 percent" as scene-setting for
the exercise rather than a number this exact dataset is meant to reproduce to the decimal, since
the bug itself, a non-match rate being reported as if it were the match rate, is identical
either way. What matters more to me is that the corrected query lands on exactly 96.0% against
the ~96% you told me to expect. That's a much harder number to hit by accident, and it's the
one I actually reproduce precisely.

## The corrected query

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
```

<img width="1496" height="1052" alt="725166C9-706D-4D13-A70B-9F7BDD9ADA9E" src="https://github.com/user-attachments/assets/429b2cfb-623e-4852-b178-9cb70a30a248" />

## My verdict, up front

Both the audit and the data turned out to be wrong, in this order of impact:

1. **The audit query had an inverted filter.** This is the dominant cause of the 4% vs 96% gap.
2. **The audit query also had a type/format mismatch in the join.** A real bug, but a smaller
   contributor.
3. **The warehouse is genuinely missing 20 records.** This one isn't a query bug at all, it's
   why the true rate is 96% and not 100%.

Here's how I got to each of those.

## Issue 1: the filter was backwards

`weekly_match_audit.sql` computes:

```sql
COUNT(*) FILTER (WHERE w.patient_key IS NULL) / COUNT(*)
```

After a `LEFT JOIN`, `w.patient_key IS NULL` means "no matching warehouse row," in other words,
a **non-match**. The query calls this `match_rate_pct` anyway, so it's been reporting the miss
rate and labeling it as the match rate. It should be filtering on `IS NOT NULL`.

Here's the query exactly as written, run against the data:

```sql
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE w.patient_key IS NULL) / NULLIF(COUNT(*), 0), 1)
FROM crm_export c
LEFT JOIN warehouse w ON w.patient_key = c.contact_id
WHERE c.created_at >= '2026-07-01' AND c.created_at < '2026-07-08';
-- match_rate_pct: 10.1
```

And here's the same join, same period, with only the filter direction flipped:

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

That one-word change takes the reported number from 10.1% to 89.9%. Most of the gap between
"4%" and "96%" comes down to this single line.

## Issue 2: a formatting mismatch was hiding real matches

`warehouse.patient_key` isn't consistent: most rows are a plain 5-digit string (`10249`), but
30 rows are zero-padded out to 8 digits (`00010249`). `crm_export.contact_id` is never padded.
Since the join compares these as exact text, `w.patient_key = c.contact_id`, those 30 warehouse
rows can never match, even though they're the same patient as their CRM counterpart.

Here are all 30 of the zero-padded rows, so you can see exactly what I mean:

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

Normalizing both sides of the join with `::bigint` (`w.patient_key::bigint = c.contact_id::bigint`)
recovers all 30 of these, and I checked it doesn't introduce any false positives: every one of
the 500 `contact_id` values and all 480 `patient_key` values are purely numeric, so the cast is
safe and lossless both ways, and there are no duplicate `contact_id` or `patient_key` values
that could cause the join to fan out and inflate the count.

That takes matches from 444 to 474 out of 494, which is 96.0%.

### One more thing worth mentioning, though it didn't change the score

The period filter compares `created_at` as a plain string or timestamp literal
(`created_at >= '2026-07-01'`). Six CRM rows carry a `+08:00` offset instead of `+00:00`
(`2026-06-30T23:30:00+08:00`, contact_ids 10001 to 10006). In this dataset, those six rows get
excluded correctly no matter how you compare them: `2026-06-30T23:30:00+08:00` is
`2026-06-30T15:30:00Z`, genuinely before the period starts, and it happens to sort before
`'2026-07-01'` as plain text too. So it doesn't move the number here. I still think it's worth
casting explicitly to `timestamptz` and comparing against explicit UTC bounds, which is what
`corrected_audit.sql` does, because a differently-offset timestamp could cross a date boundary
the other way and give a wrong answer under naive string comparison. I'm flagging this as
hardening for the future, not as something that caused the reported 4%.

## Issue 3: 20 contacts really aren't in the warehouse

After fixing both query issues above, 20 of the 494 in-period CRM contacts still don't have a
matching warehouse row, no matter how I normalize the key. These are genuinely absent from
`warehouse`, not a formatting artifact.

Here are those 20 rows, so you can see for yourself:

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

These 20 records are the reason the true rate is 96.0% and not 100%. I can't tell you from the
SQL alone whether that's expected (say, warehouse ingestion lag for very recent contacts) or an
actual problem, that's a question for whoever owns the warehouse pipeline. What I can tell you
for certain is that the gap is real, not a query artifact.

## How I reasoned through this

1. I started from what you told me: the audit reports ~4%, you expected ~96%. A gap that big
   between a reported rate and its complement, 4% and 96% add up to 100%, is usually the
   signature of an inverted condition somewhere, not a data quality problem. Data problems
   degrade a rate; they don't flip it into its complement. So that's the first thing I checked,
   and I confirmed it by running the query as-written and then only flipping
   `IS NULL` to `IS NOT NULL`.
2. With that fixed, the rate was 89.9%, not yet 96%, so I knew there was a second, real issue.
   I went looking directly at the join keys for format mismatches, a classic cause of joins
   silently missing rows, and that's how I found the zero-padded `patient_key` values.
3. After normalizing the key format, 20 rows still didn't match, under any normalization I
   tried. At that point the only explanation left was a genuine data gap, which I confirmed by
   checking that those 20 `contact_id`s exist in `crm_export` but appear nowhere in `warehouse`,
   regardless of formatting.

## How I checked myself before calling this done

- I recomputed the final number two independent ways: once as a single query with the
  `bigint`-normalized join and explicit `timestamptz` bounds (`corrected_audit.sql`), and once
  by building it up issue by issue (filter flip to 89.9%, then padding fix to 96.0%), to make
  sure the final number decomposes cleanly into the two query fixes plus the residual gap, with
  nothing left unexplained.
- Before trusting the `bigint` cast, I checked it was actually safe: `contact_id !~ '^[0-9]+$'`
  and `patient_key !~ '^[0-9]+$'` both returned zero rows, so every value in both columns is
  purely numeric, and a `GROUP BY ... HAVING count(*) > 1` on each column also returned zero
  rows, so there's no duplicate key that could make the join fan out and inflate either count.
- I cross-checked the period boundary both as a plain string comparison and as an explicit
  `::timestamptz` cast against UTC bounds, and both gave the same 494-row denominator, so the
  `+08:00`-offset rows are handled correctly either way in this particular dataset.
- I traced all 20 unmatched rows back to source: confirmed each one exists in `crm_export`, and
  confirmed none of them exists in `warehouse` under an exact match, a zero-padded match, or a
  numeric-cast match, ruling out a fourth formatting variant before I called it a genuine gap.
