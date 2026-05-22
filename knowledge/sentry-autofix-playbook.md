# Sentry Autofix Playbook

How AI agents (Seer, Claude Code, Continue, Cursor, etc.) should handle issues
flagged by Sentry in this codebase. Read this before proposing any fix that
originated from a Sentry issue link, breadcrumb trail, or stack trace.

PharmaGuide is a consumer-facing supplement-safety app. Wrong output can cause
real-world harm. Speed never beats accuracy here.

## Non-negotiable invariants

Any fix must preserve all of these. If a fix can't, stop and escalate to a
human reviewer instead of forcing it through.

1. **Severity order is sacred:** `contraindicated > avoid > caution > monitor > safe`.
   Never reorder, alias, or "normalize" these enum values.
2. **Never display `safe` when `mapped_coverage < 0.3`.** If a fix changes the
   verdict-rendering path, run the existing low-coverage tests.
3. **FitScore is computed fresh, never persisted.** Do not add caching,
   memoization, or persistence to any FitScore code path.
4. **No health data in Supabase.** Never add a Supabase call, payload, or sync
   path that includes ingredients, stack contents, conditions, medications,
   profile fields, DOB, or anything derived from them.
5. **No invented clinical content.** Do not synthesize evidence levels,
   interaction text, contraindications, or scoring weights. If the original
   bug is "missing data," surface that — don't paper over it.
6. **`evidence_level` must always render** on any interaction warning that
   reaches the UI. Don't silence it to dodge a null.

## Required scrubbing (Sentry breadcrumbs already enforce this)

`lib/services/crash_reporting_service.dart` blocks the following keys from
ever reaching Sentry. If you're proposing a fix that adds new logging or
breadcrumbs, double-check that none of these slip through unscrubbed:

`email, password, token, auth, authorization, api_key, apikey,
supabase_anon_key, gemini_api_key, sentry_dsn, access_token, refresh_token,
health, medication, medications, condition, conditions, ingredient,
ingredients, stack, profile, dob, birthdate`

A "fix" that disables `beforeSend` / `beforeBreadcrumb` scrubbing is a
regression, not a fix. Reject it.

## Fix-proposal checklist

Before opening a PR for a Sentry-flagged issue, confirm:

- [ ] Root cause is named in the PR description — not just symptoms.
- [ ] The smallest possible diff. No drive-by refactors. Max 3 files unless
      the task obviously requires more (see `AGENTS.md`).
- [ ] `flutter analyze --fatal-infos` passes locally or in CI.
- [ ] `flutter test` passes — including the test that reproduces the bug.
- [ ] If the bug was in a verdict / severity / scoring path, the existing
      low-coverage and severity-ordering tests still pass.
- [ ] PR is labeled `auto-fix-proposal` and `needs-human-review`.
- [ ] PR is **not** set to auto-merge. A human merges every Sentry-driven fix.

## When to stop and ask

Open a question instead of pushing code if any of these are true:

- The Sentry issue spans both `pharmaguide_core.db` (read-only) and
  `user_data.db` (read-write) — schema/contract changes need explicit review.
- The fix would change a contract documented in `FLUTTER_DATA_CONTRACT_V1.md`
  or `FINAL_EXPORT_SCHEMA_V1.md`.
- The bug looks like missing/wrong clinical data rather than a code error.
  Data fixes go through the pipeline, not a Flutter PR.
- The stack trace points into generated code (`*.g.dart`, `*.drift.dart`).
  Regenerate via `make gen`; don't hand-edit.

## Sentry MCP tools you'll actually use

The Sentry MCP server (configured in `.mcp.json`) exposes these tools to any
AI agent attached to this repo:

- `find_issues`, `get_issue_details` — pull the actual stack trace and
  breadcrumb trail before proposing a fix. Don't guess from the title.
- `analyze_issue_with_seer` — runs Sentry's Seer to produce a root-cause
  analysis. **Paid Sentry only.** PharmaGuide currently runs on free
  Sentry, so this tool will return an error — do your own root-cause
  analysis instead. If it's later available, read it but don't trust it
  blindly: Seer doesn't know PharmaGuide's safety invariants — you do.
- `find_releases` — confirm the issue's affected release matches what's on
  this branch before "fixing" something that may already be fixed.
- `search_events` — look at frequency and user impact. A 1-event issue isn't
  worth the same PR overhead as a 10k-event issue.

## Loop discipline

If three rounds of fixes haven't closed the Sentry issue, stop iterating and
write a comment explaining what was tried and where you're stuck. Don't keep
re-kicking — that's how good code gets broken in pursuit of a bad diagnosis.

## Safety-invariant gate (Layer 2)

CI enforces the four non-negotiable invariants automatically. Every PR —
human-authored or agent-authored — must pass them before merge:

- `test/safety_invariants/severity_order_test.dart` — locks
  `contraindicated > avoid > caution > monitor > informational > safe`,
  weights, and `fromString` aliases.
- `test/safety_invariants/low_coverage_not_safe_test.dart` — verifies that
  `mappedCoverage < 0.3` always yields `FitAssessmentState.limitedFit`
  from `FitScoreService.calculate` and that the `< 0.3` boundary is strict.
- `test/safety_invariants/no_health_in_supabase_test.dart` — locks
  `stack_sync_queue._rowToRemote` to an explicit column allowlist and
  scans the rest of `lib/` for forbidden health tokens (`conditions`,
  `medications`, `dob`, `birthdate`, `fit_score`, etc.) appearing near
  any Supabase `.upsert/.insert/.update` call.
- `test/safety_invariants/fit_score_non_persistence_test.dart` — scans
  Drift tables, `shared_preferences` keys, and Riverpod providers to
  verify nothing persists FitScore.

**Do not modify these tests to make a fix pass.** If a test fails, that's
the gate doing its job. Either revise the fix to satisfy the invariant or
escalate to a human reviewer who can decide whether the invariant itself
needs to change (rare, and never agent-initiated).

## Autofix routine + slash command (Layer 3)

Two surfaces exist for running this playbook against a real Sentry issue:

- **Scheduled routine** (`.claude/routines/sentry-autofix.md`) — runs
  twice daily on Anthropic's cloud via Claude Code Routines. Triages
  Sentry, picks the highest-impact unresolved issue from the last 24h,
  opens at most one draft PR per cycle. Setup is in
  `docs/SELF_HEALING_SETUP.md`. The routine prompt embeds the hard
  prohibitions from this playbook so the agent cannot drift even if
  someone forgets to remind it.
- **On-demand slash command** (`.claude/commands/fix-sentry-issue.md`)
  — fires the same loop interactively. Invoke as
  `/fix-sentry-issue PHARMAGUIDE-XYZ` in any Claude Code surface, or
  `/fix-sentry-issue` with no args to pick the top unresolved issue.

If you find yourself patching either file to make a fix work, stop —
the right answer is almost always to fix the diagnosis, not the
guardrails.
