---
description: Triage in-app beta feedback (pg.kind=beta_feedback) — summarize, correlate with Sentry errors, and only open a draft PR for a confidently-diagnosed code/UX bug. Optional arg filters to one category.
argument-hint: "[bug|confusing_result|wrong_product_data|missing_product|feature_request|other]"
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, mcp__sentry__*, mcp__github__*
---

You are running the on-demand version of the PharmaGuide beta-feedback
triage loop. It mirrors `.claude/routines/triage-feedback.md`.

## Inputs

Category filter (optional): `$ARGUMENTS`
- If a category is given, restrict triage to that category.
- If omitted, triage all categories from the last 7 days.

## What beta feedback is (and is not)

Each `pg.kind=beta_feedback` event carries only a category, an impact level,
the build/release, `pg.catalog_version`, `auth_state`, and route breadcrumbs
(always `/profile` — the sheet opens from Settings). There is **NO free text
and NO product identifier**: prose was routed to the support inbox, never to
Sentry. Feedback is a signal to **summarize and correlate**, not a
self-contained bug report.

## Hard rules (non-negotiable)

These mirror `knowledge/sentry-autofix-playbook.md` and the Layer 2 gate.
**If any would be violated, stop and ask the user.**

1. **Read the playbook first** — `knowledge/sentry-autofix-playbook.md`, in
   full, before any code. Then read
   `.claude/learnings/feedback-triage-lessons.md`.
2. **Never modify `test/safety_invariants/`.**
3. **Severity order is sacred.**
4. **No health data to Supabase.**
5. **`mapped_coverage < 0.3` is never "safe".**
6. **FitScore is computed, never persisted.**
7. **Draft PR only**, labeled `beta-feedback` + `needs-human-review`. Never
   auto-merge.
8. **Minimum surface.**

## Workflow

1. **Pull feedback.** Query Sentry MCP for `pg.kind=beta_feedback` events
   (last 7 days). Group by `feedback.category`, then `feedback.impact` and
   `release`. Count volume; note spikes vs the prior week.

2. **Route by category:**
   - `wrong_product_data` / `missing_product` → **counter only.** No product
     ID, no prose → not actionable tickets. Summarize volume/trend and STOP
     for these. Do NOT open a PR or a Flutter→Pipeline handoff. Point to the
     support inbox and the failed-scan / missing-UPC queue for specifics.
   - `feature_request` / `other` → summarize only. Human product triage.
   - `bug` / `confusing_result` → correlate with open Sentry **error** issues
     on the same release/surface/timeframe. Note correlations on those
     issues. Open a draft fix PR ONLY when a correlated error gives a
     confident root cause and no fix is already on main (grep the issue ID;
     compare release to main). Otherwise summarize and hand to a human.

3. **If you open a PR**, run the gate locally:
   ```bash
   flutter test test/safety_invariants/
   flutter analyze --fatal-infos && flutter test
   ```
   Branch `claude/feedback-<slug>`, draft, labels `beta-feedback` +
   `needs-human-review`. Body: the signal (category/impact/build), the
   correlated Sentry issue URL, root cause, files + rationale, a "Safety
   check" section, and "Human review required before merge."

4. **Report.** Present the digest to the user (per-category counts, impact
   split, spikes, correlations, any PR link).

## When to abort

Stop and surface to the user if: the diagnosis isn't confident; a fix would
touch a safety-invariant test, the Severity enum, the 0.3 threshold, the
FitScore contract, or a Supabase write; or more than one `beta-feedback`
draft PR is already open. Feedback with no correlated error is almost never
enough to fix — say so rather than guessing in code.
