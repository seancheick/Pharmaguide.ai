# Feedback triage — lessons

Memory for the beta-feedback triage loop (`.claude/routines/triage-feedback.md`
and `/triage-feedback`). Append a lesson whenever a run produces noise or a
rejected PR. Newer lessons override older ones if they conflict.

---

## Pattern: treating a low-context feedback counter as an actionable ticket

- **Trigger:** a `wrong_product_data` or `missing_product` feedback event —
  or a bare `bug`/`confusing_result` with no correlated Sentry error issue.
- **What the agent would try:** open a PR, or write a Flutter→Pipeline
  handoff entry, from the count alone.
- **Why rejected:** beta-feedback events carry no product ID and no prose
  (prose goes to the support inbox, never to Sentry). A count is not a
  reproducible report; manufacturing a ticket from it is noise the pipeline
  team can't act on.
- **What to do instead:** record the volume/trend in the rolling "Beta
  feedback digest" issue and stop. Name the support inbox and the in-app
  failed-scan / missing-UPC queue as the source of actionable detail. Only
  open a code PR when a `bug`/`confusing_result` spike CORRELATES with a
  specific open Sentry *error* issue that yields a confident root cause.
