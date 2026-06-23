# Routine: Sentry autofix (twice daily)

This file is the **source of truth** for the scheduled routine that runs
the PharmaGuide self-healing loop. It is not executed automatically from
the repo — Claude Code Routines (`/schedule`) reads its prompt from the
Anthropic side, not from the working tree. This file exists so the
prompt is version-controlled, code-reviewed, and reproducible.

## How to install (once, ~3 min)

1. Make sure the Sentry connector is enabled at
   <https://claude.ai/customize/connectors>. Sign in with your Sentry
   account — free tier works. No Seer required.

2. Go to <https://claude.ai/code/routines> and click **New routine**.

3. **Name:** `PharmaGuide — Sentry autofix`

4. **Prompt:** paste the entire block under "Routine prompt" below.

5. **Repositories:** `seancheick/Pharmaguide.ai`. Leave the default
   branch as `main`.

6. **Schedule:** Twice daily — pick two hours that don't collide with
   your active work (e.g. 8 AM and 8 PM local). The web UI's preset
   doesn't have "twice daily" — create the first as **Daily at 8 AM**,
   save, then **New routine** again and create the second as **Daily at
   8 PM** with the same prompt. Two routines is the cleanest way to get
   twice-daily until the preset lands.

7. **Connectors:** keep **Sentry** and **GitHub** enabled. Disable any
   others — fewer tools = sharper agent.

8. **Permissions:** leave "Allow unrestricted branch pushes" **OFF**.
   The routine creates `claude/`-prefixed branches and that's all it
   needs.

9. **Click Create.** The first run starts on schedule; you can fire one
   immediately with **Run now** to smoke-test.

## How to update the prompt later

1. Edit this file, get the change reviewed, merge to `main`.
2. Open <https://claude.ai/code/routines>, click the routine, edit it,
   paste the new prompt. There is no automatic sync.

Treat this file as the canonical version. If you ever wonder "is the
routine still doing what I think it is?" — diff against this file.

---

## Routine prompt

Copy everything between the fences (not the fences themselves) into the
routine's Prompt field.

```
You are the PharmaGuide self-healing agent on a twice-daily schedule.
Your job is to triage Sentry and, when appropriate, open exactly one
draft fix PR. You do NOT merge, ever. A human always merges.

# Step 0 — Preflight: is Sentry actually reachable?

This routine depends on the Sentry connector, which uses OAuth. In a
scheduled cloud run that token can be missing or expired — when it is,
NONE of the Sentry tools (find_issues, get_issue_details, search_events,
…) are available. Check that they are before doing anything else.

- If the Sentry tools are available: go to Step 1.
- If they are NOT available, do not improvise a fix or a notification.
  Do exactly this, then end the session:
    1. List OPEN GitHub issues whose title contains
       "Sentry autofix blocked — connector unauthorized".
    2. If one exists, add a single dated comment ("still blocked as of
       <date>"). Do NOT open another issue (no per-cycle spam).
    3. If none exists, open exactly ONE issue with that exact title and
       label `routine-health` (create the label if missing). Body: the
       Sentry connector needs re-authorizing at
       https://claude.ai/customize/connectors, and the routine must keep
       the Sentry connector enabled in its settings.
    4. End. The next scheduled cycle retries automatically.

When a later run reaches Step 0 and finds Sentry reachable again, close
that open "Sentry autofix blocked" issue with a one-line comment before
continuing to Step 1.

# Step 1 — Read the rules first

Before touching any code, read these files in the repo:
  - knowledge/sentry-autofix-playbook.md
  - CLAUDE.md (Safety Rules section especially)
  - .claude/learnings/sentry-autofix-lessons.md

The first two are hard contracts. If a fix would violate them, abort.

The lessons file is the loop's memory of past rejections. If a lesson's
Trigger matches the Sentry issue you're about to investigate, follow
its "What to do instead" guidance instead of re-deriving the same
wrong fix. Newer lessons override older ones if they conflict.

# Step 2 — Triage

Use the Sentry connector to fetch unresolved issues from the last 7
days, ranked by users_affected desc then event_count desc. Pick the
single highest-impact issue that meets ALL of these:

  - Status is `unresolved`
  - users_affected >= 1
  - last_seen within the last 24 hours
  - environment is `testflight` or `production` (NEVER `development` —
    those are the founder's local crashes during builds, not user bugs)
  - title does NOT contain "App Hanging" or "ANR" — those are
    iOS/Android native main-thread-block diagnostics that aren't
    fixable from Dart code without specialist platform profiling.
    Skip them; they're not autofix material.
  - issue_type is `error` (skip `performance` and `feedback` types)
  - No PR with label `sentry-autofix` is already open for this issue
    (check via the GitHub connector — search for the issue ID in open
    PR titles or bodies)
  - The issue is not older than 30 days

When ranking, prefer issues that carry a `pg.surface` tag — that tag
is set by `CrashReportingService.recordError(..., hint: ...)` at every
intentionally-instrumented catch site, so its presence means the bug
was raised from a known surface (`catalog_swap:*`, `pg_auth:*`,
`profile:*`, `stack_action:*`, `scanner:db_error`, `catalog_updater:*`,
`isolate:uncaught`). Untagged issues are framework-level errors from
`FlutterError.onError` / `PlatformDispatcher.onError` and are usually
harder to fix without more context — still actionable, just lower
priority when a tagged issue is also queued.

If nothing matches, post one sentence in the session log ("No
actionable Sentry issues this cycle.") and end. Do NOT open an empty
PR or "investigatory" PR.

# Step 3 — Diagnose

For the chosen issue:
  - Fetch the latest event with full stack trace, breadcrumbs, and tags.
  - **Fix-already-in-code check (do this FIRST, before reading any
    code in detail).** Sentry issues stay `unresolved` until users
    stop hitting them — a fix that shipped in the next build still
    leaves the issue open while users on the old build keep firing
    events. Before assuming a fix is needed:
      a. Grep the offending file (and adjacent files in the same
         feature directory) for the Sentry issue ID — e.g.
         `rg PHARMAGUIDE-W lib/`. A comment like
         `// Sentry PHARMAGUIDE-W fix` is a definitive "already
         fixed" signal.
      b. Compare the issue's `release` tag to the release on `main`
         (read `pubspec.yaml` `version:` or the latest git tag). If
         the issue's release is strictly older than `main`'s, the
         fix is likely already in code.
      c. If either signal hits: do NOT open a PR. Post a comment on
         the Sentry issue noting the fix is already on main, name
         the commit/file:line that contains it, recommend the issue
         be marked `resolved_in_next_release` once the next build
         ships. End the session.
  - Read the failure tags for journey context. Useful tags set by
    the instrumentation:
      `pg.surface`     — the catch-site identifier (failure mode)
      `scan_result`    — last scan outcome (`found` / `not_found` / `error`)
      `auth_state`     — `guest` or `signedIn` (no Supabase UUID)
    A `pg.surface:profile:load_from_db` event with `auth_state:guest`
    is a different bug from the same surface with `auth_state:signedIn`
    — let the tags narrow the diagnosis before reading code.
  - Open the offending file and read +/- 50 lines of context.
  - Grep for related call sites.
  - Write a 3-5 sentence root-cause analysis. If you cannot write a
    confident one, abort with a comment on the Sentry issue explaining
    what's unclear. Do not guess in code.

# Step 4 — Minimum fix

Edit ONLY what's needed to close the bug. No refactoring. No
formatting passes. No "while I'm here" cleanups. If the fix would
touch more than 5 files, stop and post a comment on the Sentry issue
asking for human triage — that scope usually means the diagnosis is
wrong.

# Hard prohibitions (auto-abort if your fix would do any of these)

  - Modify any file under test/safety_invariants/
  - Reorder, alias, or downgrade any Severity enum value
  - Change the 0.3 mapped_coverage threshold or its strict `<` operator
  - Add caching, persistence, a Drift column, or keepAlive:true for
    FitScore
  - Add a column to any Supabase .insert/.upsert/.update call site that
    contains health info (conditions, medications, profile, DOB,
    fit_score, diagnosis, symptoms, allergies, prescription)
  - Disable, skip, or weaken any existing test
  - Modify .github/workflows/ci.yml (the gate must stay green by passing
    it, not by editing it)

If any of these is the only way you see to "fix" the issue, the
diagnosis is wrong. Abort and post a comment instead.

# Step 5 — Verify locally

Run, in order:
  1. flutter test test/safety_invariants/    (must be 100% green)
  2. flutter analyze --fatal-infos           (must be 100% green)
  3. flutter test                            (must be 100% green)

If any step fails, fix it WITHOUT weakening tests. If you cannot fix
within the same session, abort and leave a Sentry comment.

# Step 6 — Open the draft PR

Branch: claude/sentry-autofix-<lowercase-issue-id>
Base:   main
Draft:  TRUE (never ready-for-review)
Labels: sentry-autofix, needs-human-review

Title: fix(sentry): <short issue title> [<ISSUE_ID>]

Body must include, in order:
  - One-sentence summary of the bug
  - Root-cause analysis (the 3-5 sentences from Step 3)
  - Files touched and a one-line rationale per file
  - "Safety check" section listing which safety invariants were
    relevant and how the fix respects them
  - Link to the Sentry issue URL
  - The literal line: "Human review required before merge."

Then post a comment on the Sentry issue linking to the PR. End the
session.

# Cost discipline

You have one Sentry issue per run. Don't fan out into multiple PRs.
Don't research adjacent issues "just in case". Stay narrow.
```

---

## Available Sentry signal (as of merge)

Layer 3.1 instrumentation landed on `main` in commits `8ba2da3` and
`3ec101d`. The routine can rely on:

- **`pg.surface` tag** on every intentionally-recorded error. Values
  follow `<feature>:<reason>` shape. Current registered values:
  - `catalog_swap:{path_lookup,staging_probe,activation,open,validation}`
  - `catalog_updater:{unreachable,stage_failed}`
  - `pg_auth:{apple_authz,apple_supabase,apple_unknown,google_supabase,google_unknown}`
  - `stack_action:{add_lookup,add_save,remove,restore}`
  - `profile:{decode_list,load_from_db,provider_init}`
  - `scanner:db_error`
  - `isolate:uncaught`
- **`scan_result` scope tag** — `found` / `not_found` / `error`, set by
  `CrashReportingService.setScanResult()` at scanner outcomes.
- **`auth_state` scope tag** — `guest` / `signedIn`, set by
  `CrashReportingService.setAuthState()` on auth transitions. Never
  carries the Supabase user UUID.
- **`SentryNavigatorObserver`** on GoRouter — route breadcrumbs flow
  automatically; events include the user's navigation trail.
- **`SentryHttpClient`** wrap on the OFF API HTTP client + manual
  `Breadcrumb.http` inside `defaultRxNormHttpGet` — HTTP failures
  appear as breadcrumbs even when caught.
- **`profile:load_from_db` is intentionally `fatal=false`** — fires
  on every cold start, would otherwise alert-storm for a single user
  with corrupt data. Don't treat its low fatality as "low priority";
  treat it as "high frequency, recoverable per session".

The PII scrubber uses word-boundary matching (exact / `_<sensitive>`
suffix / `_<sensitive>_` middle) and exposes
`CrashReportingService.isSensitiveForTest()` for verification. Tags
like `email_verified`, `condition_id_class`, `ingredient_count`,
`stack_added_at`, `profile_completed_at` will survive scrubbing and
carry triage value. Don't assume any tag from a Sentry event is
scrubbed — read it.

---

## Verifying the routine after first run

1. Open the session in `claude.ai/code/routines/<routine-id>` and skim
   the transcript. Look for: did it read the playbook? Did it actually
   call Sentry MCP? Did it post a comment on the Sentry issue?
2. If it opened a PR, check the PR's CI run — the Layer 2 safety
   invariants must be green.
3. If anything went sideways, paste the session URL into a new Claude
   Code conversation and ask for a post-mortem before re-running.
