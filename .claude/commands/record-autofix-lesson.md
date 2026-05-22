---
description: Record a lesson from a rejected sentry-autofix PR so the next run doesn't repeat the mistake. Pass the PR URL or number as the argument.
argument-hint: "<pr-url-or-number>"
allowed-tools: Read, Edit, Bash, mcp__github__pull_request_read, mcp__github__list_pull_requests
---

You are running the Layer 5 learning-capture flow for the PharmaGuide
self-healing loop.

## Inputs

PR URL or number: `$ARGUMENTS`

- If the argument is a full URL (e.g.
  `https://github.com/seancheick/Pharmaguide.ai/pull/42`), use it as-is.
- If it's a number (e.g. `42`), assume the repo is
  `seancheick/Pharmaguide.ai`.
- If no argument is given, list the 5 most recently-closed PRs with
  the `sentry-autofix` label and ask the user which one to record a
  lesson for.

## What to do

1. **Read the PR end-to-end** via the GitHub MCP tools:
   - PR title, body, author
   - Files changed (diff summary; full diff if small)
   - All review comments, issue comments, and the close reason
   - Whether it was closed-without-merge, reverted, or rewritten

2. **Read the existing lessons file** at
   `.claude/learnings/sentry-autofix-lessons.md`. If a lesson already
   captures this rejection pattern, say so — propose updating that
   entry instead of adding a duplicate.

3. **Draft a new lesson entry** using the template in the lessons
   file. Aim for 4-6 sentences per field:

   - **Trigger:** describe the *kind* of Sentry issue this rejection
     applies to (e.g. "Sentry issue with null-pointer in
     features/product_detail/**"), not just the specific issue ID.
     The trigger is a pattern, not a fingerprint.
   - **What the agent tried:** one-line summary of the actual diff.
     Be specific — vague summaries don't help the next run.
   - **Why it was rejected:** quote or paraphrase the reviewer's
     comment in their own words. If multiple reviewers commented,
     synthesize.
   - **What to do instead:** concrete guidance. If the right answer
     is "abort and ask the human", say so explicitly — many
     rejections are "this needs human judgement, not a code fix".

4. **Show the draft to the user** as a plain-text block. Wait for
   them to approve, edit, or reject before writing.

5. **On approval, prepend the lesson** to the "Recorded lessons"
   section of `.claude/learnings/sentry-autofix-lessons.md`. Newest
   at top. Include the PR URL as the reference.

6. **Commit the change** with a message like
   `chore(self-healing): record lesson from autofix rejection [PR #N]`.
   Do NOT push automatically — the user pushes when they're ready.

## What NOT to do

- **Do not** edit any other file — only the lessons file.
- **Do not** speculate on rejection reasons the reviewer didn't
  actually give. If the close reason is unclear (PR was closed with no
  comment), ask the user before drafting.
- **Do not** invent a lesson if the PR was rejected for a benign
  reason like "duplicate of #X" or "no longer needed after upstream
  fix". Those aren't learnings — they're noise. Tell the user and
  stop.
- **Do not** include sensitive content from the PR (any data the
  scrubber would block in Sentry breadcrumbs). The lessons file is
  committed to the repo and visible publicly if the repo goes public.

## When to abort

- The PR was merged successfully — no lesson to record.
- The PR is still open — wait until it's actually closed-without-merge.
- The PR has no review comments and was closed silently — there's no
  signal to learn from. Tell the user to add a comment to the PR
  explaining the rejection, then re-run this command.
