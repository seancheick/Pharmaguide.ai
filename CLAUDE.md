# PharmaGuide Flutter App

Consumer-facing supplement safety app. Offline-first, privacy-first. Medical-grade accuracy required.

## Commands

```bash
make run          # flutter run + all --dart-define secrets injected from .env
make test         # flutter test
make check        # analyze + test (CI gate)
make gen          # dart run build_runner build --delete-conflicting-outputs
make verify-supabase  # confirm anon key is live
make verify-bundle    # bundled DB matches Supabase storage (pre-release safety)
make help         # every target — this list is a subset and drifts
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

## Diagnosis Protocol (any "why does the app show X?" question)

A value reaching a widget crossed six layers. Name the one you're reading **before** explaining anything:

```
pipeline artifact → Supabase (detail blob / OTA catalog) → bundled pharmaguide_core.db
   → Drift query → Riverpod provider → widget
                                    ( user_data.db is a separate read-write lane )
```

1. Name the layer and the file/provider before any claim. "The app shows a false UL warning" is
   not a diagnosis until you know whether the bad value is in the blob, the DB, the query, or the render.
2. One live probe on one real product before any narrative — `sqlite3 assets/db/pharmaguide_core.db`
   for the row, or a widget test for the render. Print the driver field; the first flag is rarely the driver.
3. Wrong once → re-read the production file, never patch the probe. Parallel Codex sessions and
   automated `chore(catalog)` commits move HEAD mid-conversation: re-read, don't recall.
4. **Stale bundled catalog ≠ current pipeline defect.** Before fixing a data bug seen in the app,
   reproduce it through the current pipeline output. (Learned the hard way — see the 79
   impossible-%UL warnings that turned out to be stale bundled evidence.)
5. One brain: if the bad value came from the pipeline, the fix belongs in the pipeline. An app-side
   correction that overrides a pipeline verdict is a defect even when it makes the screen look right.
6. Outside-voice claims (Codex, Grok, pasted reviews) are hypotheses — reproduce before agreeing
   OR refuting. "You're right" needs the same evidence as "you're wrong."

## Definition of Done (any change)

1. Re-read the final diff — not your memory of it.
2. One adversarial pass on your own work: try to REFUTE it. Null blob, offline, empty stack,
   unknown verdict, `mapped_coverage < 0.3`, signed-out. Fix what you find before showing it.
3. Climb the ladder and paste the output — all rungs stay, pick the right one:
   `flutter analyze` → focused `flutter test test/<area>` → broad affected sweep →
   `make check` (analyze + full tests, the CI gate) → `make verify-bundle` before a release.
4. **Rendering, theme, and layout changes need a device or simulator screenshot.** Green widget
   tests have shipped invisible text more than once; only the device caught it.
5. "Done" without command output is not done.

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
