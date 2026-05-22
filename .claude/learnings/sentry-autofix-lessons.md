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

<!--
  No lessons recorded yet. The first sentry-autofix PR rejection will
  populate this section via /record-autofix-lesson <pr-url>.
-->
