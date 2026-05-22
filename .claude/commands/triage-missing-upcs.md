---
description: Process a paste of the local failed-scan queue and generate a triage report for the pipeline backfill. Run this when you want to ingest the missing products into the next OTA DB build.
allowed-tools: Read, Write, Bash, Grep, mcp__github__*
---

You are running the Layer 4 missing-UPC triage flow for PharmaGuide.

## Context

The Flutter app records every barcode the local catalog can't resolve
into a Drift table called `user_failed_scans` (UPC + attempt_count +
first_seen + last_seen, no user identifier — see
`lib/data/database/tables/failed_scans_table.dart` for the privacy
contract).

This data lives on-device. To triage it, the user runs this command
with a paste of the queue rows.

## Inputs

The user will paste rows from `user_failed_scans` after this command
is invoked, in one of these formats:

- **CSV:** `upc,attempt_count,first_seen,last_seen` (header optional)
- **JSON:** array of `{upc, attempt_count, first_seen, last_seen}`
  objects
- **sqlite3 default output:** `upc|attempt_count|first_seen|last_seen`
  pipe-separated

If the user's paste doesn't match any of those, ask them once for the
format. Don't guess silently.

To dump the queue from a Mac terminal:

```bash
sqlite3 ~/Library/Containers/<bundle-id>/Data/Documents/user_data.db \
  -header -csv \
  'SELECT upc, attempt_count, first_seen, last_seen
   FROM user_failed_scans
   ORDER BY attempt_count DESC, last_seen DESC
   LIMIT 100'
```

(If the user doesn't know their bundle path, suggest they use the
Drift Inspector via DevTools instead.)

## What to do

1. **Parse the paste.** Extract `upc`, `attempt_count`, `last_seen`
   for each row. Discard any row where `upc` is empty, not numeric,
   or shorter than 8 digits — those are almost always test data or
   QR misfires.

2. **Rank and triage.** Sort by `attempt_count` desc, then `last_seen`
   desc. The top of the list is the highest-value backfill work.

3. **Generate the triage report.** For each of the top 10 UPCs,
   produce a Markdown row:

   ```
   | UPC | Tries | Last seen | DSLD lookup | OFF lookup |
   ```

   - `DSLD lookup` is `https://dsld.od.nih.gov/search?q=<upc>`
   - `OFF lookup` is `https://world.openfoodfacts.org/product/<upc>`

   Inline both URLs so the user can click straight through.

4. **Write the report** to `docs/missing_upcs_<YYYY-MM-DD>.md`
   (use today's date, in the user's local timezone if known).

5. **Show the report inline** so the user sees it without opening
   the file.

6. **Suggest next steps** in three bullets at the end:

   - Run `backfill_upc.py` in `~/Downloads/dsld_clean/scripts/` against
     the UPCs that resolved on DSLD.
   - Manually source the UPCs that didn't resolve on either lookup
     (likely discontinued or international products).
   - Once the pipeline rebuild ships, delete the report file — the
     UPCs will fall out of the local queue as users re-scan
     successfully.

## What NOT to do

- **Do not** open a GitHub Issue, post a Sentry comment, or push
  anything anywhere. This command is a local-triage helper, not an
  autonomous loop.
- **Do not** include any data from the paste beyond `upc`,
  `attempt_count`, `last_seen`. If the paste includes other columns
  (e.g. someone added a `user_id` later in violation of the safety
  invariant), surface that as a warning at the top of the report and
  stop — don't propagate the leak.
- **Do not** modify `lib/data/database/tables/failed_scans_table.dart`
  or `test/safety_invariants/failed_scans_no_pii_test.dart` from this
  command. Schema changes need the human in the loop.

## When to abort

- The paste is empty or has fewer than 3 rows — surface a one-line
  "queue is too small to triage usefully, come back in a week" and
  stop.
- The paste contains columns outside the allowlist (see above).
- Today's report already exists with the same top entries — say so
  and skip the rewrite.
