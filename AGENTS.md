# PharmaGuide Flutter app — agent constitution

Shared by Claude, Codex and every other agent (OpenCode, Continue, Cline, Aider, Gemini CLI). Claude
loads it through `@AGENTS.md` in CLAUDE.md. **This is the one canonical rule file**; CLAUDE.md holds
only Claude-specific extras. Deeper context lives in `knowledge/` — read it on demand.

## Project

- Consumer supplement-safety app: offline-first, privacy-first, medical-grade accuracy. Never
  invent health logic, clinical meaning, contraindications, scores, evidence levels or pipeline
  contracts.
- Dart/Flutter · Riverpod · GoRouter · Drift (SQLite).
  - `assets/db/pharmaguide_core.db`: read-only catalog, replaced via OTA. Query it for counts;
    never hard-code them.
  - `user_data.db`: read-write profile/stack/cache, never touched by OTA.
  - Supabase: detail blobs, auth, OTA catalog, and signed-in supplement-stack sync through the
    audited path.
- The data comes from the pipeline repo at `/Users/seancheick/Downloads/dsld_clean`
  (github PharmaGuide_Pipeline). Its AGENTS.md is the other half of the contract below.

## Commands — `make`, never a raw `flutter run` or `flutter build`

```bash
make run              # flutter run with every --dart-define from .env
make test             # flutter test
make check            # analyze + full tests (the CI gate)
make gen              # build_runner
make verify-supabase  # anon key is live
make verify-bundle    # bundled DB matches Supabase storage (pre-release)
make help             # every target
```

- Without the Makefile `DART_DEFINES` (Supabase, Sentry, Google client IDs), a build is broken.
- A fresh worktree runs no tests until you copy `assets/db/interaction_db.sqlite` and run `make gen`
  (both are gitignored).
- CI is often red on the dart-format step alone: pre-existing debt, not a broken build.

## Safety rules (non-negotiable)

- Never store profile data, medications, allergens, conditions, goals or FitScore in Supabase.
  Signed-in supplement-stack sync goes only through the audited stack-sync path; medication rows
  never sync.
- FitScore is never persisted; it is recomputed from the current profile every time.
- Never display "safe" when `mapped_coverage < 0.3`.
- Severity order is sacred: contraindicated > avoid > caution > monitor > safe.
- Always show `evidence_level` on interaction warnings.
- All JSON parsing handles null or missing fields safely.
- Never add a free-text-to-Sentry box: `captureFeedback` messages are not key-scrubbed. Send
  structured category + impact only; prose goes to mailto.
- **Copy voice:**
  - App-authored strings are calm-advisory. No "Stop" / "Avoid" / "Do not" / all-caps; use
    "Worth a conversation with your doctor" / "PharmaGuide does not recommend".
  - Pipeline- and clinician-authored text (Dr Pham's, banned-ingredient warnings) passes through
    verbatim, and app copy never mirrors its imperatives.

## One brain — the pipeline decides, the app renders

- Quality uses `quality_tier` / `quality_score_status`; catalog safety uses
  `product_safety_status`; completion uses `quality_assessment_status` through
  `catalog_product_semantics.dart`. A quality score or tier never determines safety.
  `POOR` is only a legacy cached quality alias, never a safety finding or a newly emitted verdict.
  Read legacy `verdict` only through the existing conservative compatibility owner.
- Never add app-side logic that overrides a pipeline verdict (`skip_ul_check`, `over_ul`,
  `ul_gate_eligible`). If a bad value came from the pipeline, fix it in the pipeline. An app-side
  correction is a defect even when the screen looks right.
- Dose safety has central owners: `doseSuppressionGuardsPass`, `Severity.isHard` / `isActionable`
  (`lib/core/constants/severity.dart`), `dose_units`, `canonicalizeIngredientName`. Reuse them;
  never re-derive.
- **Owner Check** before creating any field, provider, state, util or file:
  - `rg` the name and its stem in `lib/`, and in the pipeline repo for data fields. Extend what
    exists.
  - Record it in the plan or handoff as `Owner: path::symbol — evidence: <command>` or
    `No owner: searched …`, followed by `Will NOT create: …`.
- Don't weaken the identity guard to make a test pass. Unresolved-identity rows never drive scoring
  or evidence. Identity matching keys on the unique `source_path`, never on raw label text.

## Cross-repo contract (pipeline → app)

| Seam | Pipeline owner | App reader |
|---|---|---|
| Public quality score | `scripts/score_supplements_v4.py::score_product_v4` → `scripts/scoring_v4/scored_artifact.py` (config `scripts/scoring_v4/config/quality_score.json`) | `quality_score_v4_100` column in `products_core_table.dart`; the app never recomputes it |
| Core DB columns | `scripts/core_export_model.py` | `lib/data/database/tables/products_core_table.dart`, `lib/data/database/products_core_projection.dart` |
| Detail-blob keys | `scripts/audit_contract_sync.py::BLOB_TOP_LEVEL` | `lib/data/supabase/detail_blob_service.dart`, `lib/data/providers/detail_blob_provider.dart` |
| Enums / structures | pipeline code | `knowledge/pipeline-reference.md` (check it against the pipeline code) |

- **Consuming a new field:** it must already be declared on the pipeline side. Parse it null-safely.
- **Removing a reader:** check whether the pipeline still emits the field or has retired it, and
  change both repos together.
- Blob flags are real JSON booleans; SQLite core flags are 0/1.
- A stale bundled catalog is not a current pipeline defect. Reproduce a data bug through the
  current pipeline output before fixing it.

## Truth order and autonomy

1. Current code, the bundled DB and the live blob.
2. Pipeline contracts and `knowledge/architecture-decisions.md`.
3. Tests.
4. Docs, memory and chat, as evidence only.

Parallel sessions and automated `chore(catalog)` commits move HEAD mid-conversation, so `git fetch`
and re-read before any claim.

- **Decide from these rules and act; don't queue decisions.** Inspect, probe and check history.
  Ask Sean only for a semantic decision: health or safety behavior, a new persisted or synced field,
  a new verdict meaning, copy policy, or a release.
- **Bugs you find:** fix them with a failing test first, in their own commit, then return to the
  task. Don't turn a fix into a redesign. On an infrastructure branch, record app defects with
  evidence and spawn a separate fix instead.
- **Outside-voice claims** (Codex, other models, reviews) are hypotheses. Reproduce them before
  agreeing or refuting.

## Diagnosis protocol ("why does the app show X?")

A value crosses six layers: pipeline artifact → Supabase (blob / OTA) → bundled
`pharmaguide_core.db` → Drift query → Riverpod provider → widget. `user_data.db` is a separate
read-write lane.

1. Name the layer and the file or provider before making any claim.
2. Run one live probe on one real product first: `sqlite3 assets/db/pharmaguide_core.db` for the
   row, or a widget test for the render. Print the driver field; the first flag is rarely the
   driver.
3. If you were wrong once, re-read the production file. Never patch the probe.

## Changes and dead code

- Make the smallest safe change in the fewest files; if it fans out widely, say why. No drive-by
  refactors, no new packages or docs without need, no bulk edits of JSON data.
- **Delete dead code and fields once proven dead; don't park them.** Zero references alone isn't
  proof. Also check generated code, providers wired by name, routes, platform code, assets, and
  the pipeline contract. Remove the code, its tests and its docs together.

## Definition of done

1. Re-read the final diff.
2. Adversarial pass: null blob, offline, empty stack, unknown verdict, `mapped_coverage < 0.3`,
   signed out.
3. Climb the ladder and paste the output: `flutter analyze` → focused `flutter test test/<area>` →
   broad affected sweep → `make check` → `make verify-bundle` before a release. Focused-green alone
   is not proof.
4. Rendering, theme and layout changes need a device or simulator screenshot; green widget tests
   have shipped invisible text.
5. "Done" without command output is not done.

## Knowledge placement

| Knowledge | Lives in |
|---|---|
| Current task state | `.claude/state/CURRENT_HANDOFF.md` |
| Decisions | `knowledge/architecture-decisions.md` |
| Lessons | a regression test first, then `knowledge/lessons-learned.md` |
| Personal preferences | agent memory |
| History | git |

`SPRINT_TRACKER.md` is large: open it only when the task is a tracked sprint item.
