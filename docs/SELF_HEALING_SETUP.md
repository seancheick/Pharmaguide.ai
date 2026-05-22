# Self-Healing Setup

PharmaGuide ships with a three-layer self-healing system. Each layer is
independent — you can install them in order and each one is useful on
its own.

| Layer | What it does | Where it lives | Status |
|---|---|---|---|
| 1 | Sentry MCP + agent guardrails: any agent that reads `.mcp.json` (Claude Code CLI, Claude Code on the Web, Cursor, Continue, opencode) can query Sentry directly. No code is auto-generated or auto-merged. | `.mcp.json` + `knowledge/sentry-autofix-playbook.md` | ✅ Shipped |
| 2 | Medical-safety quality gate: five invariant tests that CI runs on every PR — auto-generated or human. Blocks any change that would silently break the severity order, the low-coverage rule, the no-health-to-Supabase rule, the FitScore-never-persisted rule, or the failed-scan-queue-no-PII rule. | `test/safety_invariants/` + `.github/workflows/ci.yml` | ✅ Shipped |
| 3 | Autofix routine: a scheduled Claude Code Routine triages Sentry twice a day and opens a draft PR with the minimum fix. Layer 2 stands between any auto-PR and `main`. | `.claude/routines/sentry-autofix.md` + `.claude/commands/fix-sentry-issue.md` | ✅ Shipped |
| 4 | Missing-UPC sensor: every barcode the catalog can't resolve lands in a local `user_failed_scans` Drift table (UPC + counts only, no user identifier). A `/triage-missing-upcs` slash command produces a ranked report with DSLD + OFF lookup URLs for pipeline backfill. | `lib/data/database/tables/failed_scans_table.dart` + `.claude/commands/triage-missing-upcs.md` | ✅ Shipped (this branch) |
| 5 | Lessons file: rejected autofix PRs get recorded so the next run doesn't repeat the same mistake. The Layer 3 routine + slash command both read it before touching code. | `.claude/learnings/sentry-autofix-lessons.md` + `.claude/commands/record-autofix-lesson.md` | ✅ Shipped (this branch) |

**No code is ever auto-merged.** Even with all three layers green, a
human always merges PharmaGuide changes.

---

## Layer 1 — Sentry MCP + agent guardrails

### What it does

1. **Sentry MCP server** — `.mcp.json` registers the official hosted
   Sentry MCP server, scoped to `bbr-technology/pharmaguide`. Any agent
   that speaks MCP gains tools to query Sentry issues, events,
   breadcrumbs, and releases.
2. **Agent guardrails** — `knowledge/sentry-autofix-playbook.md` defines
   the medical-safety invariants every agent must preserve when
   proposing a Sentry-driven fix.

### One-time setup (~3 min)

Two prerequisites; everything else is already in the repo.

1. **Enable the Sentry connector** at
   <https://claude.ai/customize/connectors>. Sign in with your Sentry
   account. **Free Sentry works** — you do not need Seer or any paid
   feature for Layers 1, 2, or 3.

2. **Confirm `.mcp.json` is in the project root** (it is). The hosted
   server uses OAuth — the first time any agent calls a Sentry tool it
   opens a browser for you to authorize. No token lives in this repo.

### Optional: Sentry Seer (paid Sentry only)

Seer is Sentry's own root-cause analysis service. PharmaGuide does not
depend on it — the Layer 3 routine performs root-cause analysis itself
via the agent. If you later upgrade to a paid Sentry plan and want Seer
analyses to auto-attach to issues:

1. Sentry → **Settings → Integrations → GitHub** — connect if not
   already (cloud GitHub only; not self-hosted).
2. Sentry → **Settings → Seer SCM Settings** — add
   `seancheick/pharmaguide.ai`.
3. Sentry → **Settings → Seer Project Settings** — link this project
   to the repo.
4. Keep **"PR creation"** **OFF**. The Layer 3 routine creates PRs
   correctly for a medical app; letting Seer also open PRs would race
   on the same issues.

### How to use Layer 1

From any agent that reads `.mcp.json` (Claude Code CLI, Claude Code on
the Web, Cursor, Continue, opencode):

> "Pull the top 5 unresolved Sentry issues from the last 7 days, ranked
>  by user impact. Summarize the top one — don't write any code yet."

Or for a specific issue:

> "Investigate Sentry issue `PHARMAGUIDE-XYZ`. Read the stack trace, the
>  breadcrumb trail, the related code. Tell me what's broken and what
>  a minimal fix would touch. Don't open a PR."

For on-demand fix proposals (still gated by Layer 2):

> "/fix-sentry-issue PHARMAGUIDE-XYZ"

The slash command lives at `.claude/commands/fix-sentry-issue.md` —
edit it there if you want to tweak the behavior.

---

## Layer 2 — Medical-safety quality gate

Five tests under `test/safety_invariants/` lock down the
non-negotiables from `CLAUDE.md`:

| Test | What it locks |
|---|---|
| `severity_order_test.dart` | The `Severity` enum's declaration order, weights, and `fromString` aliases. |
| `low_coverage_not_safe_test.dart` | `FitScoreService.calculate` returns `limitedFit` when `mapped_coverage < 0.3`, with strict `<` boundary. |
| `no_health_in_supabase_test.dart` | The only Supabase write call site (`stack_sync_queue._rowToRemote`) is locked to an explicit column allowlist; every other Supabase write in `lib/` is scanned for forbidden health tokens. |
| `fit_score_non_persistence_test.dart` | No Drift table, `SharedPreferences` key, or Riverpod `keepAlive: true` ever persists FitScore. |
| `failed_scans_no_pii_test.dart` | The Layer 4 `FailedScans` table only carries UPC + aggregate counts. No user_id, device_id, profile, location, or any other identifier may be added without an explicit privacy review. |

CI (`.github/workflows/ci.yml`) runs them on every PR alongside the
existing test suites. **Do not modify these tests to make a fix pass.**
If a test fails, that's the gate doing its job.

---

## Layer 3 — Sentry autofix routine

A scheduled Claude Code Routine that triages Sentry twice a day and
opens at most one draft PR per cycle.

### Why a routine, not a GitHub Action

Routines run on Anthropic-managed cloud infrastructure using your
Max-plan subscription. **No `ANTHROPIC_API_KEY` is needed; no secrets
live in GitHub.** They read your repo's `.mcp.json`, your committed
playbook, and the Sentry connector you authorized for Layer 1.

### One-time setup (~5 min)

Open `.claude/routines/sentry-autofix.md` for the full step-by-step.
Short version:

1. <https://claude.ai/code/routines> → **New routine**.
2. Paste the prompt block from `.claude/routines/sentry-autofix.md`.
3. Repository: `seancheick/Pharmaguide.ai`.
4. Schedule: **Daily at 8 AM** (create a second routine at 8 PM for the
   twice-daily cadence — the UI's preset doesn't have "twice daily"
   yet, two daily routines is the cleanest path).
5. Connectors: keep **Sentry** and **GitHub** on, disable the rest.
6. **Allow unrestricted branch pushes:** OFF.
7. Click **Create**, then **Run now** once to smoke-test.

### Hard guarantees baked into the routine

- Draft PRs only — never ready-for-review, never auto-merge.
- One open auto-PR at a time (the routine checks before opening).
- Branch naming: `claude/sentry-autofix-<lowercase-issue-id>`.
- Always labeled `sentry-autofix` + `needs-human-review`.
- Cannot modify `test/safety_invariants/`, the severity enum, the 0.3
  coverage threshold, `ci.yml`, or any Supabase write column set
  without aborting. These are baked into the prompt as hard
  prohibitions.

### What's NOT in Layer 3

- No real-time webhook trigger. Twice-daily polling is the cadence;
  faster requires a paid Anthropic plan with API triggers or a
  Cloudflare relay.
- No marketing-site coverage. Mirror this setup into the marketing
  repo when you point me at it.
- No instrumentation upgrade yet. The routine is only as good as the
  Sentry signal it triages, and most user-impacting errors are
  currently caught and swallowed without reaching Sentry. See
  `docs/SELF_HEALING_LAYER_3_1_PLAN.md` for the planned upgrade —
  budget it for after the first wider beta or once a real bug slips
  through invisibly.

---

## Layer 4 — Missing-UPC sensor

The Flutter scanner used to drop failed scans on the floor. Now every
unresolvable barcode lands in a local Drift table
(`user_failed_scans`) with attempt count + first/last timestamps.

### Privacy contract

The table stores **only the UPC and aggregate counts**. No user_id,
device_id, session, location, or any identifier that ties the data to
a person. UPCs are public product identifiers (the same string is
printed on every bottle of that product worldwide) — they are not
health data. The contract is locked by
`test/safety_invariants/failed_scans_no_pii_test.dart`.

### Triage flow

Triage is intentionally manual in v1 — auto-syncing to Supabase or
auto-opening GitHub Issues would invert the cost/benefit until volume
justifies it. Revisit if the queue hits >100 unique UPCs/week.

1. Dump the queue from a Mac terminal:
   ```bash
   sqlite3 ~/Library/Containers/<bundle-id>/Data/Documents/user_data.db \
     -header -csv \
     'SELECT upc, attempt_count, first_seen, last_seen
      FROM user_failed_scans
      ORDER BY attempt_count DESC, last_seen DESC
      LIMIT 100'
   ```
2. Open any Claude Code surface, run `/triage-missing-upcs`, paste
   the rows. The command produces a ranked Markdown report with DSLD
   + OFF lookup URLs and writes it to
   `docs/missing_upcs_<YYYY-MM-DD>.md`.
3. Run `backfill_upc.py` in `~/Downloads/dsld_clean/scripts/` against
   the UPCs that resolved on DSLD. Manually source the rest.
4. The next OTA database build picks the new products up; users
   re-scanning will succeed and the rows fall out of the queue
   naturally (no cleanup needed).

---

## Layer 5 — Lessons file

Every time an autofix PR is rejected — closed without merge, reverted,
or rewritten beyond recognition — the rejection reason gets recorded
in `.claude/learnings/sentry-autofix-lessons.md`. The next autofix
run reads the lessons file before touching code, so the loop doesn't
repeat the same mistake.

### Recording a lesson

1. Reject the autofix PR with a comment explaining why (one sentence
   is enough; the agent can flesh it out).
2. Run `/record-autofix-lesson <pr-url>`.
3. Claude reads the PR + your comments, drafts a lesson entry, shows
   you the draft. Approve, edit, or reject.
4. On approval, the entry is prepended to the lessons file and
   committed locally. Push when you're ready.

### How the routine uses it

The Layer 3 routine and the `/fix-sentry-issue` slash command both
read the lessons file in Step 1 of their workflow (after the
playbook, before touching code). If a lesson's Trigger matches the
current Sentry issue, the agent follows that lesson's "What to do
instead" guidance — including "abort and ask the human" if that's
the right answer.

### Pruning

Prune aggressively. Once an underlying code path changes, lessons
about that path become noise that nudges the agent toward stale
fixes. If the file grows beyond ~20 lessons, consolidate or delete
the oldest.

---

## Verifying the system works end to end

1. **Layer 1**: in any Claude Code surface, ask "what's the latest
   unresolved Sentry issue?" The agent should call `find_issues` via
   MCP and return real data. If it doesn't, `.mcp.json` isn't being
   read — check the file is at the project root and your agent has been
   restarted.

2. **Layer 2**: run `flutter test test/safety_invariants/` locally.
   All 17 tests should pass green. Push a deliberately-broken commit
   (e.g. reorder two severity enum values) to a throwaway branch and
   verify CI rejects it.

3. **Layer 3**: in `claude.ai/code/routines/<your-routine-id>` click
   **Run now**. Watch the session transcript — the agent should fetch
   Sentry, read the playbook, either open a draft PR or post a "no
   actionable issues" log line. The first draft PR you get is the real
   smoke test.

4. **Layer 4**: scan a barcode that you know isn't in the catalog
   (any random book ISBN works for the smoke test). Confirm the row
   landed in `user_failed_scans`:
   ```bash
   sqlite3 ~/Library/Containers/<bundle-id>/Data/Documents/user_data.db \
     'SELECT * FROM user_failed_scans'
   ```
   Run `/triage-missing-upcs` against the dumped rows — you should
   get a Markdown report with DSLD + OFF lookup links.

5. **Layer 5**: this one verifies itself when you reject your first
   autofix PR. Run `/record-autofix-lesson <pr-url>`, approve the
   drafted lesson, then on the next routine run confirm the agent
   followed the new guidance instead of re-proposing the same fix.
   Until you have a real rejection, the file stays empty — that's
   fine.

If step 1 fails, none of the other layers help — fix MCP first.
