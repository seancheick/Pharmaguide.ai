---
description: Investigate a Sentry issue and open a draft fix PR. Pass an issue ID like PHARMAGUIDE-XYZ as the argument, or omit to use the top unresolved issue.
argument-hint: "[PHARMAGUIDE-XYZ]"
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, mcp__sentry__*, mcp__github__*
---

You are running the on-demand version of the PharmaGuide self-healing loop.
The user asked you to investigate (and likely fix) a Sentry issue and open a
draft pull request.

## Inputs

Issue ID (optional): `$ARGUMENTS`

- If a Sentry issue ID was provided in the arguments (format
  `PHARMAGUIDE-XXX` or a Sentry shortlink), use that one.
- If no argument was given, query Sentry MCP for the top unresolved
  issue from the last 7 days, ranked by user impact (`users_affected`
  desc, then `event_count` desc). Filter to
  `environment:[testflight, production]` and skip any issue whose
  title contains "App Hanging" or "ANR" (those are iOS/Android
  native main-thread-block diagnostics — not actionable from Dart).
  Pick exactly one — don't try to batch-fix.

## Hard rules (non-negotiable)

These mirror `knowledge/sentry-autofix-playbook.md` and the Layer 2 safety
gate. **If any of these would be violated, stop and ask the user.**

1. **Read the playbook first.** Read `knowledge/sentry-autofix-playbook.md`
   in full before writing any code. Every rule there overrides anything
   you might "want" to do for elegance or refactoring.
2. **Never modify `test/safety_invariants/`.** Those tests are the gate;
   tampering with them defeats the entire system. If a safety-invariant
   test is the reason your fix doesn't pass, the fix is wrong — not the
   test.
3. **Severity order is sacred.** Never reorder, alias, or downgrade any
   `Severity` enum value.
4. **No health data to Supabase.** If your fix touches any Supabase
   `.insert/.upsert/.update` call site, it must not add a column that
   contains health info (conditions, medications, profile, DOB, FitScore).
5. **`mapped_coverage < 0.3` is never "safe".** Don't change the 0.3
   threshold or the strict `<` comparison.
6. **FitScore is computed, never persisted.** Don't add caching, Drift
   columns, or `keepAlive: true` for it.
7. **Draft PR only.** Never mark the PR ready for review. Never call
   `enable_pr_auto_merge`. Label the PR `sentry-autofix` and
   `needs-human-review`.
8. **Minimum surface.** Touch the smallest number of lines that fixes the
   bug. No refactoring, no "while I'm here" cleanups, no formatting
   changes outside the diff.

## Workflow

1. **Fetch the issue.** Use Sentry MCP tools (`get_issue_details`,
   `get_event_details`, `list_events`) to pull the stack trace, the most
   recent event, the breadcrumb trail, and the release/version. Identify
   the offending file and line.

2. **Read the playbook.** Open `knowledge/sentry-autofix-playbook.md`.
   Pay attention to the "Safety-invariant gate" section.

   **Then read the lessons file** at
   `.claude/learnings/sentry-autofix-lessons.md`. If a recorded lesson
   matches the kind of Sentry issue you're looking at, follow the "What
   to do instead" guidance from that lesson — don't re-derive the wrong
   fix the loop already learned to avoid.

3. **Read the offending code.** Open the file from the stack trace. Read
   ±50 lines of context. Find related call sites with `Grep`. Do *not*
   skim — guess-fixes are how this loop poisons itself.

4. **Diagnose.** Write a 3-5 sentence root-cause analysis. This becomes
   the PR body. If you can't confidently explain the root cause, stop and
   ask the user — don't speculate in code.

5. **Propose the minimum fix.** Edit only what's needed. If the fix would
   touch >5 files, stop and ask the user first — that scope usually means
   the diagnosis is wrong, not that the bug is sprawling.

6. **Run the safety gate locally.**
   ```bash
   flutter test test/safety_invariants/
   ```
   If anything red, fix it without weakening the test. If you can't, stop
   and ask.

7. **Run the full test suite.**
   ```bash
   flutter analyze --fatal-infos && flutter test
   ```

8. **Open a draft PR** on branch
   `sentry-autofix/<lowercase-issue-id>` against `main`:
   - Title: `fix(sentry): <short issue title> [<ISSUE_ID>]`
   - Draft: yes
   - Labels: `sentry-autofix`, `needs-human-review`
   - Body: include the root-cause analysis, the diff summary, and a link
     back to the Sentry issue URL.

9. **Post a Sentry comment** (via `mcp__sentry__update_issue` or a
   suitable add-comment tool) linking back to the PR. This closes the
   loop visually for anyone monitoring Sentry.

## When to abort

Abort and surface the situation to the user — don't push partial work —
if any of these are true:

- The diagnosis isn't confident after reading the code.
- The fix would touch a safety-invariant test file.
- The fix would change the Severity enum, the 0.3 coverage threshold, or
  the FitScore non-persistence contract.
- The fix would add a column to a Supabase write.
- More than one `sentry-autofix` draft PR is already open. (We
  intentionally cap at one to keep the human review queue sane.)
- The Sentry issue is older than 30 days. Old issues are usually about
  versions of the code that have already shifted underneath the
  stack trace.

In all abort cases, post a one-paragraph explanation as a comment on the
Sentry issue and end your turn.
