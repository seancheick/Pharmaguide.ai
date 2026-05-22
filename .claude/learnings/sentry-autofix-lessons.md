# Sentry-autofix lessons

This file is the autofix agent's institutional memory. Every time a
sentry-autofix PR is rejected — closed without merge, reverted, or
re-worked beyond recognition — the rejection reason gets recorded here.
The next autofix run reads this file before proposing anything, so the
same mistake doesn't ship twice.

**Format:** newest at top. One section per lesson. Use the template
below — or run `/record-autofix-lesson <pr-url>` to have Claude draft
the entry from the PR for you.

```
## Pattern: <short name describing the trap>

- **Trigger:** When you see a Sentry issue that looks like <X>
- **What the agent tried:** <one-line summary of the rejected fix>
- **Why it was rejected:** <reviewer's reason in their own words if possible>
- **What to do instead:** <correct approach, or "abort and ask">
- **Recorded:** YYYY-MM-DD
- **Reference PR:** <url>
```

How the agent uses this file:

1. The Layer 3 routine and the `/fix-sentry-issue` slash command both
   read this file as Step 1.5 of their workflow (after the playbook,
   before touching code).
2. If the current Sentry issue matches a recorded pattern's Trigger,
   the agent follows the "What to do instead" guidance instead of
   inventing a new fix.
3. If two patterns conflict, the newer one wins (it reflects the most
   recent reviewer judgement).

How the user uses this file:

1. When you reject an autofix PR, run `/record-autofix-lesson <pr-url>`.
   Claude reads the PR + your review comments and drafts an entry.
2. Review the draft, edit if needed, approve. It gets prepended to the
   "Recorded lessons" section below.
3. The next autofix run picks it up automatically — no restart needed.

If this file gets longer than ~20 lessons, prune the oldest ones (or
consolidate duplicates). The agent only needs the patterns that are
still relevant; ancient lessons that no longer apply are noise.

---

## Recorded lessons

## Pattern: Fix already in current code, Sentry issue still open

- **Trigger:** When a Sentry issue's `release` tag is older than the
  most recent release on `main`, and a quick search of the offending
  file already shows a fix comment or the change that would address
  the bug.
- **What the agent tried:** On 2026-05-22, the routine would have
  attempted to "fix" PHARMAGUIDE-W (`magic_link_sheet.dart` null check
  via `Navigator.of`). The fix shipped on 2026-05-16 in beta.2 — the
  file already has `useRootNavigator: true` plus a comment referencing
  the Sentry issue ID. But the issue is still firing for users on
  beta.1 who haven't received the next TestFlight build.
- **Why it would be rejected:** Opening a PR that re-fixes a fixed
  bug is noise. The reviewer would close it as duplicate, lose trust
  in the loop, and the cycle would repeat next time another delayed
  issue surfaces.
- **What to do instead:** Before proposing any code change, do these
  two checks:
  1. Grep the offending file (and adjacent files in the same feature)
     for the Sentry issue ID. A comment like `// Sentry PHARMAGUIDE-X
     fix` is a definitive "already fixed" signal.
  2. Compare the Sentry issue's `release` tag to the release on
     `main` (read pubspec.yaml `version:` or git tags). If the
     issue's release is strictly older than `main`'s, the fix is
     likely already in code; mark the Sentry issue as
     `resolved_in_next_release` instead of opening a PR.
  Only propose a new fix if neither check finds prior work.
- **Recorded:** 2026-05-22
- **Reference PR:** none — caught during the Layer 3 smoke test, before
  any PR was opened.

<!--
  Older lessons go below. Newest at top — newer lessons override
  older ones when they conflict.
-->
