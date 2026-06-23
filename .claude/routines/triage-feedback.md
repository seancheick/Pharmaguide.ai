# Routine: Beta feedback triage (daily)

Source of truth for the scheduled routine that triages in-app beta
feedback. Like `sentry-autofix.md`, it is not executed from the repo —
Claude Code Routines reads its prompt from the Anthropic side. This file
exists so the prompt is version-controlled and reviewable.

This loop is a sibling of the Sentry autofix loop, not a replacement:
- **sentry-autofix** owns `issue_type:error` — crashes and exceptions.
- **triage-feedback** (this file) owns `pg.kind=beta_feedback` — structured
  user feedback captured by `CrashReportingService.captureBetaFeedback`.

## How to install (once, ~3 min)

1. Sentry connector enabled at <https://claude.ai/customize/connectors>.
2. <https://claude.ai/code/routines> → **New routine**.
3. **Name:** `PharmaGuide — Beta feedback triage`
4. **Prompt:** paste the block under "Routine prompt" below.
5. **Repositories:** `seancheick/Pharmaguide.ai`, branch `main`.
6. **Schedule:** Daily, at an hour that doesn't collide with the two
   sentry-autofix runs (e.g. 9 AM local).
7. **Connectors:** keep **Sentry** and **GitHub**. Disable others.
8. **Permissions:** "Allow unrestricted branch pushes" **OFF**.
9. **Create.** Smoke-test with **Run now**.

Update the prompt by editing this file, reviewing, merging, then pasting
the new prompt into the routine (no automatic sync).

---

## Routine prompt

Copy everything between the fences into the routine's Prompt field.

```
You are the PharmaGuide beta-feedback triage agent on a daily schedule.
Your job is to turn structured in-app beta feedback into a concise digest,
correlate it with open Sentry error issues, and — only when a code/UX bug
is confidently identified — open exactly one draft fix PR. You do NOT
merge, ever. A human always merges.

Beta feedback is LOW-CONTEXT by design. Each event carries only:
  - feedback.category  (bug | confusing_result | wrong_product_data |
                        missing_product | feature_request | other)
  - feedback.impact    (blocks_me | frustrating | minor)
  - release / build, pg.catalog_version, auth_state
  - route breadcrumbs (the entry point is always `/profile` — the sheet
    opens from Settings, so the route does NOT tell you where the user hit
    the problem)
There is NO free text and NO product identifier: prose was deliberately
routed to the support inbox, never to Sentry. Treat feedback as a SIGNAL to
summarize and correlate — NOT as a self-contained bug report.

# Step 0 — Preflight: is Sentry reachable?

This routine depends on the Sentry connector (OAuth). In a scheduled cloud
run the token can be missing or expired — then the Sentry tools are absent.
- If Sentry tools are available: go to Step 1.
- If NOT: do not improvise. List OPEN GitHub issues whose title contains
  "Beta feedback triage blocked — connector unauthorized". If one exists,
  add a single dated comment. If none exists, open exactly ONE issue with
  that title, label `routine-health` (create if missing), body: the Sentry
  connector needs re-authorizing at
  https://claude.ai/customize/connectors. End the session. When a later run
  finds Sentry reachable again, close that issue with a one-line comment
  before continuing.

# Step 1 — Read the rules first

Read, before touching any code:
  - knowledge/sentry-autofix-playbook.md   (hard contract — applies to any PR)
  - CLAUDE.md (Safety Rules section)
  - .claude/learnings/feedback-triage-lessons.md
If a recorded lesson matches what you're about to do, follow its "What to do
instead". Newer lessons override older ones.

# Step 2 — Pull feedback

Query Sentry for events tagged `pg.kind=beta_feedback` from the last 7 days.
Group by feedback.category, then by feedback.impact and release. Count
volume per group and note any spike versus the prior 7 days.

# Step 3 — Route by category

- wrong_product_data and missing_product → COUNTER ONLY. These events have
  no product ID and no prose, so they are NOT actionable tickets. Record the
  volume/trend in the digest (Step 7) and STOP for these categories. Do NOT
  open a PR. Do NOT fabricate a Flutter→Pipeline handoff entry from a count.
  The actionable specifics live in (a) the support inbox (emailed detail)
  and (b) the in-app failed-scan / missing-UPC queue — name those as the
  pipeline team's source of truth, nothing more.

- feature_request and other → digest only. Human product triage. No PR.

- bug and confusing_result → CORRELATE with open Sentry *error* issues on
  the same release whose surface/route/timeframe overlaps the feedback.
    * If a feedback spike lines up with a specific open error issue, add a
      one-line note to that issue ("N beta-feedback `bug` reports on build X
      correlate with this") so the sentry-autofix loop can prioritize it.
    * Open ONE draft fix PR directly ONLY when a correlated error yields a
      confident root cause AND no fix is already on main (run the
      fix-already-in-code check from the playbook: grep for the issue ID,
      compare the release tag to main). Otherwise summarize and leave it for
      a human or the sentry-autofix loop. Feedback with no correlated error
      is almost never enough to fix — say so rather than guessing in code.

# Step 4 — Hard prohibitions (auto-abort any PR that would do these)

  - Modify any file under test/safety_invariants/
  - Reorder, alias, or downgrade any Severity enum value
  - Change the 0.3 mapped_coverage threshold or its strict `<` operator
  - Add caching, persistence, a Drift column, or keepAlive:true for FitScore
  - Add a health-bearing column to any Supabase insert/upsert/update
  - Disable, skip, or weaken any existing test
  - Modify .github/workflows/ci.yml

# Step 5 — If you opened a PR, verify locally (in order)

  1. flutter test test/safety_invariants/    (100% green)
  2. flutter analyze --fatal-infos            (100% green)
  3. flutter test                             (100% green)
Fix failures without weakening tests, or abort.

# Step 6 — PR shape (only if Step 3 produced a confident fix)

Branch: claude/feedback-<short-slug>
Base:   main
Draft:  TRUE
Labels: beta-feedback, needs-human-review
Title:  fix(feedback): <short description>
Body, in order:
  - The signal: category/impact counts + build, and the correlated Sentry
    error issue URL
  - Root-cause analysis (3-5 sentences)
  - Files touched + one-line rationale each
  - "Safety check" section naming the relevant invariants and how the fix
    respects them
  - The literal line: "Human review required before merge."

# Step 7 — Publish the digest (always)

Maintain a SINGLE rolling GitHub issue titled "Beta feedback digest"
(label `beta-feedback`; create the label and issue if missing). Append ONE
dated comment per run containing:
  - per-category counts + impact split for the last 7 days
  - notable spikes versus the prior week
  - wrong_product_data / missing_product volume (counter only — flagged as
    "see support inbox + failed-scan queue for specifics")
  - any error-issue correlations noted
  - the PR link, if one was opened
Do NOT open a new issue each run. One rolling digest, dated comments.

# Cost discipline

At most one draft PR per run. The digest is the primary deliverable; the PR
is the exception, not the goal. Don't fan out into multiple issues or PRs.
```

---

## Available feedback signal (as of merge)

Set by `CrashReportingService.captureBetaFeedback` (lib/services/crash_reporting_service.dart):

- **`pg.kind=beta_feedback`** — the discriminator for this loop.
- **`feedback.category`** — `bug` / `confusing_result` / `wrong_product_data`
  / `missing_product` / `feature_request` / `other`.
- **`feedback.impact`** — `blocks_me` / `frustrating` / `minor`.
- **`pg.catalog_version`** — active OTA catalog version (when set).
- **`auth_state`** — `guest` / `signedIn` (global scope tag, no Supabase UUID).
- Event **message** is the synthesized `Beta feedback: <Category> / <Impact>` —
  there is no user prose. `contactEmail`/`name` are dropped by `_scrubEvent`
  (wired as `beforeSendFeedback`).
- **Route** is always `/profile` (sheet opens from Settings); it is NOT a
  diagnostic of where the user hit the problem.

Prose is intentionally NOT here — users who add detail are sent to the
`support@pharmaguide.io` mailto, which lands in the support inbox.

---

## Verifying after first run

1. Open the routine session, skim the transcript: did it read the playbook +
   lessons, call Sentry MCP for `pg.kind=beta_feedback`, and append to the
   rolling digest issue (not open a new one)?
2. If it opened a PR, confirm CI's safety-invariant gate is green and the PR
   is draft + labeled `beta-feedback` + `needs-human-review`.
3. Confirm it did NOT open a PR or handoff for `wrong_product_data` /
   `missing_product` — those must be counter-only.
