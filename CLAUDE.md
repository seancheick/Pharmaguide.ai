# PharmaGuide Flutter App

Consumer-facing supplement safety app. Offline-first, privacy-first. Medical-grade accuracy required.

## Commands

```bash
make run          # flutter run + all --dart-define secrets injected from .env
make test         # flutter test
make check        # analyze + test (CI gate)
make gen          # dart run build_runner build --delete-conflicting-outputs
make verify-supabase  # confirm anon key is live
```

## Architecture

- **State:** Riverpod | **Nav:** GoRouter | **DB:** Drift (SQLite)
- `pharmaguide_core.db` — read-only, 180K products, 88 cols, replaced via OTA
- `user_data.db` — read-write, user profile/stack/cache, never touched by OTA
- Supabase — detail blob fetch, auth, OTA catalog, and signed-in supplement stack sync. Profile data, medications, and allergens stay on-device.

## Safety Rules (non-negotiable)

- NEVER store profile data, medications, allergens, conditions, goals, or FitScore in Supabase
- Signed-in supplement stack sync is allowed only through the audited stack-sync path; medication rows must never sync
- NEVER display "safe" when `mapped_coverage < 0.3`
- ALWAYS use severity order: `contraindicated > avoid > caution > monitor > safe`
- ALWAYS show `evidence_level` on interaction warnings
- FitScore is NEVER persisted — computed fresh from current profile every time
- All JSON parsing must handle null/missing fields gracefully

## Hard-won rules (from real incidents — full context in memory)

- **One brain.** The pipeline decides; the app renders. Never add app-side logic that overrides a pipeline verdict (`skip_ul_check` / `over_ul` / `ul_gate_eligible`). Find the existing util and reuse it — never re-copy.
- **Copy voice is calm-advisory.** No "Stop"/"Avoid"/"Do not"/all-caps in user-facing strings. Use "Worth a conversation with your doctor" / "PharmaGuide does not recommend". Dr Pham's authored source text passes through verbatim; Flutter-side copy never mirrors its imperatives.
- **Never add a free-text-to-Sentry box.** `captureFeedback` message isn't key-scrubbed. Structured category+impact only; prose goes to mailto.
- **Dose safety has 8 centralized SSOTs** — `doseSuppressionGuardsPass`, `Severity.isHard`/`isActionable`, `dose_units`, `canonicalizeIngredientName`, and the rest. Reuse them; never re-derive.
- **Don't weaken the identity guard to green a test.** Unresolved-identity rows must never drive scoring/evidence; the 2 red UC-II tests in a curated worktree are red *by design*.
- **Verify live, not from memory.** Parallel sessions and automated `chore(catalog)` commits move HEAD mid-conversation. Re-read the file and re-pull the DB/blob before any claim; cite line numbers from the fresh read.
- **Focused-green ≠ proof.** Run the broad affected sweep plus the release group. Identity matching keys on unique `source_path`, never raw label text. Read the design doc for exact contract keys.

## Knowledge Base

Deep context lives in `knowledge/` — read these when relevant, not by default:
- `architecture-decisions.md` — ADR log (append-only)
- `lessons-learned.md` — mistakes + root causes
- `flutter-patterns.md` — project conventions
- `debugging-playbook.md` — common issues + fixes
- `pipeline-reference.md` — pipeline data structures + enums
- `sentry-autofix-playbook.md` — guardrails when fixing Sentry-flagged issues

## Knowledge Graph

A navigable graph of the entire codebase + knowledge base lives in `graphify-out/`.
- `graph.json` — current node/edge/community counts are in `graphify-out/GRAPH_REPORT.md` (don't hardcode them here; they drift every rebuild)
- `graph.html` — interactive visualization. NOTE: skipped automatically above 5,000 nodes, so it can be stale while `graph.json` is fresh. Raise `GRAPHIFY_VIZ_NODE_LIMIT` or tighten `.graphifyignore`.
- `obsidian/` — full Obsidian vault with backlinks

Before answering architecture or "what connects to X" questions, query the graph:
```
/graphify query "your question"
/graphify path "NodeA" "NodeB"
/graphify explain "NodeName"
```
After code changes, the `post-commit` git hook auto-rebuilds for code files (detached; log at
`~/.cache/graphify-rebuild.log`). For doc/knowledge changes, run `/graphify . --update`.

⚠️ `git lfs install` **overwrites** `.git/hooks/post-commit` and `post-checkout`, silently removing
the graphify section — this froze the graph from 2026-05-06 to 2026-07-24. After any LFS
(re)install, run `graphify hook install` and confirm with `graphify hook status`. The hook also
exits 0 silently if `graphify` isn't on PATH, so an empty commit or a GUI-client commit proves
nothing.
