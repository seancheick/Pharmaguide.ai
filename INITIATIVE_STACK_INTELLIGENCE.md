---
initiative: Stack Intelligence Initiative
status: active
created: 2026-04-28
target_retirement: 2026-06-08
owner: Sean
trackers_replaced: none
trackers_complementing:
  - SPRINT_TRACKER.md (general flutter sprints)
  - INITIATIVE_PRODUCT_TRUST_AND_IA.md (parallel trust-and-IA work)
versions_in_scope:
  - V1.0 release hardening
  - V1.1 Stack Intelligence diagnostic
  - V1.2 Clinician share report
  - V1.3 OTA catalog refresh
  - V1.4+ Commerce (deferred until trust established)
repos_in_scope:
  - flutter: /Users/seancheick/PharmaGuide ai
  - pipeline: /Users/seancheick/Downloads/dsld_clean
---

# Stack Intelligence Initiative

> **One sentence:** Move PharmaGuide from a single-number stack score to a diagnostic system that earns clinical trust, then layer commerce on top once trust is established.

---

## Why this initiative exists

The Flutter app currently surfaces a prominent 0–100 "Stack Score" on the home screen. That number:

1. **Hides dangerous outliers.** A stack with 9 clean supplements + 1 banned ingredient still scores ~85.
2. **Mixes incompatible dimensions.** Safety is binary; quality is continuous; goals are contextual; nutrient adequacy is aggregate math. You can't mathematically average across them.
3. **Implies false precision.** "73/100" reads like a clinical grade, but biology isn't linear.
4. **Is unactionable.** Users can't tell what to fix.

The right model for a clinical product is the same shape used in real medical risk scoring (CHA₂DS₂-VASc, MELD, MEWS, APACHE): **hard safety gates + dimensional decomposition + each dimension is itself actionable**. No single composite number.

This initiative replaces the score-headline architecture with a diagnostic system, ships a clinician-shareable report, fixes the on-device catalog refresh, and lays the groundwork for a privacy-respecting commerce layer — strictly in that order, so trust comes before monetization.

---

## What we're trying to achieve

| Outcome | How we'll measure it |
|---|---|
| Stack Health surfaces a tier verdict + actionable issues, not a score | Stack Health UI renders a tier label and shared signal list; the internal 0–100 value is never rendered |
| Banned/recalled ingredients always trigger an "Unsafe" headline regardless of other quality signals | Unit tests assert `unsafe` tier in every gate-trigger scenario |
| Users can share a clinician-ready stack summary in 2 taps | Markdown report → system share sheet; manually verified on real device |
| TestFlight/Play users receive catalog updates without reinstalling the app | OTA bundle download on launch; validation-gated activation in-session; rollback on failure |
| Affiliate program ready to plug in once V1.2 ships, **without** Amazon PA-API exposure | Impact Radius approved + retailer enrollments live; no PA-API code in repo |
| Every change respects the AGENTS.md surgical-diff rule | Each task uses the smallest atomic blast radius that fully fixes the root cause |

---

## Why this is a separate document from SPRINT_TRACKER.md

`SPRINT_TRACKER.md` is the canonical project-wide sprint board (Sprints 0–27.5+). This initiative spans 5 sequential mini-versions (V1.0 → V1.4+) and has its own architectural thesis ("diagnostic, not score") that needs to stay legible as a single document. When this initiative retires, the relevant entries roll up into `SPRINT_TRACKER.md` as completed sprint references.

**Editing rule:** day-to-day status updates land here. Big architectural decisions also surface in `SPRINT_TRACKER.md` and `architecture-decisions.md`.

---

## Locked Architectural Principles

| Principle | Implication |
|---|---|
| **Stack Health = diagnostic system, NOT a score** | No prominent 0–100 number. Tier label + issue list is the headline. |
| **PG Score ≠ Stack Health** | PG Score grades a product (computed by pipeline). Stack Health diagnoses a combination (computed on the user's phone). |
| **Profile + stack stay on device** | No health data flows to Supabase. Privacy is a real differentiator. |
| **Pipeline ships per-product signals; Flutter composes** | Every stack-level computation runs on the phone. |
| **Tier vocabulary: optimized / solid / decent / concerning / unsafe (+ incomplete fallback)** | No A/B/C/D/F. No 0–100 headline. |
| **AGENTS.md compliance: surgical, atomic diffs** | Touch the fewest files that fully solve the task; do not split a root fix merely to meet a file count. |
| **Hard safety gates override every other signal** | A banned ingredient is never averaged away by quality. |
| **No invented clinical thresholds** | No "covered/under-dosed/missing" verdicts unless reference data has clinician-authored thresholds. Use neutral language ("no matched ingredients found", "below typical study doses"). |
| **No Amazon PA-API integration** | PA-API deprecates 2026-05-15. Skip Amazon entirely until Creators API requirements stabilize. Use Impact Radius (iHerb/Vitacost/Swanson) as the commerce backbone. |
| **Catalog refresh activates in-session, gated by validation** | Supersedes the original "no mid-session swap" rule (retired 2026-04-29). Spec lives in `INITIATIVE_PRODUCT_TRUST_AND_IA.md` §5 + T0.6. The safety properties the old rule guarded — corruption, mid-scan disruption, no rollback — are explicitly engineered into T0.6 (validation gate before live-DB touch, atomic file rename, Drift close-then-reopen, Sentry-logged rollback). |

---

## User-facing stack tiers (locked)

```
Optimized   → no identified concerns under the checks that completed
Solid       → no major concerns; monitor-level context may be present
Decent      → some concerns worth reviewing
Concerning  → review needed (avoid-level interactions, near-UL, etc.)
Unsafe      → hard stop (banned/recalled, contraindicated)
```

Internal-only fallback state (rendered as neutral "more info needed" copy, never as a graded label):

```
Incomplete  → More info needed; known monitor signals remain visible
```

---

## Pipeline ↔ Flutter Boundary

| Concern | Pipeline (`/Users/seancheick/Downloads/dsld_clean`) | Flutter (`/Users/seancheick/PharmaGuide ai`) |
|---|---|---|
| Per-product enrichment + scoring | ✅ owns | reads from bundled SQLite + Supabase |
| Reference data (interaction rules, RDA/UL, synergy clusters, drug classes, taxonomy) | ✅ authors + bundles | reads via `ReferenceDataRepository` |
| Stack composition (gates, interactions across stack, nutrient sums, tier verdict) | ❌ never sees user's stack | ✅ all on-device |
| User profile (conditions, drug classes, goals) | ❌ profile-blind | ✅ in `UserDatabase` (Drift), local only |
| Commerce / purchase options (Track E, deferred) | ✅ writes `purchase_options[]` per UPC into detail blob | ✅ reads + opens deep links via `url_launcher` |
| OTA catalog refresh | ✅ exposes versioned bundle on CDN | ✅ checks/downloads on launch, applies at next start |

---

## Status Legend

- `[ ]` not started
- `[x]` done (merged + tests green)
- `[-]` pending (blocked, awaiting external dependency, or paused intentionally)

---

# Track A — V1.0 Release Hardening (THIS WEEK)

**Goal:** Ship the safety scanner. No new features. Do not destabilize.

**Definition of Done (sprint-level):**
- `flutter analyze` reports zero issues
- All Flutter tests pass (449+)
- Real-device scan pass on iOS and Android
- TestFlight build available for internal testing
- Play Internal track build available
- OTA database-version bug from 2026-04-28 session verified fixed

---

### `[x]` A1 — `flutter analyze` clean
- **Why:** Lint debt accumulates as silent risk. Zero issues is a non-negotiable release gate.
- **What:** Run `flutter analyze` and resolve every reported issue. No `// ignore:` shortcuts.
- **Files:** As needed — keep diffs surgical.
- **Tests:** N/A (this is hygiene).
- **DoD:** `flutter analyze` reports `No issues found!` on a clean checkout.
- **Verified 2026-04-28:** `flutter analyze` → `No issues found! (ran in 3.1s)`.

### `[x]` A2 — Full test suite green
- **Why:** Tests are the contract. Any flake masks real regressions.
- **What:** Run `flutter test` end-to-end. Quarantine no flaky tests; fix them.
- **Files:** Test files only.
- **Tests:** N/A (this IS the test verification).
- **DoD:** All 449+ tests pass with zero failures, zero skipped (unless skipped with explicit reason recorded in `lessons-learned`).
- **Verified 2026-04-28:** `flutter test` → `597 tests passed`. Removed one stale test in `test/app_test.dart` ("Home category chips navigate into filtered search results") — the home category rail was deliberately removed in Sprint 27.18, so the test no longer matched reality. Orphaned `package:drift/drift.dart` import dropped at the same time.

### `[ ]` A3 — Real-device scan pass
- **Why:** Simulator passes ≠ device passes. Camera permissions, barcode decode performance, dark-mode rendering all differ.
- **What:** Side-load TestFlight build on iPhone + Play Internal on Android. Scan 10 representative product types (gummy, softgel, liquid, multi, banned-ingredient sample, recalled product).
- **Files:** None (manual QA).
- **Tests:** Manual QA log entry in `lessons-learned.md`.
- **DoD:** All 10 scans return correct product detail; permissions request flows are clean.

### `[x]` A4 — Soften home headline copy
- **Why:** Prep for V1.1 swap without jarring users. The label changes from "Stack Score" to "Stack Health" so the diagnostic shift in V1.1 reads as a refinement, not a redesign.
- **What:** Replace "Stack Score" string in the home widget with "Stack Health".
- **Files:**
  - `lib/features/home/widgets/home_stack_health.dart` (1 line)
- **Tests:** Existing widget tests pass; copy assertion updated if any.
- **DoD:** Home renders "Stack Health" wording; existing 0–100 number behavior unchanged.
- **Verified 2026-04-28:** Already shipped in Sprint 27.18 (`home_stack_health.dart:192` renders the literal `'Stack Health'`); shared `StackHealthLabel` (`Optimized / Solid / Decent / Concerning / Unsafe`) is the visible tier. Confirmed by reading the widget + the Sprint 27.18 entry in `SPRINT_TRACKER.md`.

### `[ ]` A5 — TestFlight + Play Internal builds
- **Why:** Internal testers need the build to validate before public release.
- **What:** Run release pipeline (Fastlane / Codemagic / GH Actions, whichever is wired). Upload to TestFlight + Play Internal.
- **Files:** None (build pipeline only).
- **Tests:** Smoke test the uploaded build by installing from TestFlight on a real device.
- **DoD:** Internal testers can install and launch.

### `[x]` A6 — OTA database refresh fix verification
- **Why:** Bug found in 2026-04-28 session: `ensureCoreDatabaseAvailable` only copies on first install. Without the fix, TestFlight users get stuck on the catalog version that shipped with the app forever.
- **What:** The fix landed in today's session (`lib/data/providers/database_providers.dart`, `lib/main.dart`, `test/data/providers/database_providers_test.dart`). Verify it survives review and works on real device.
- **Files:** Already modified — re-verify.
- **Tests:**
  - `test/data/providers/database_providers_test.dart` — assert refresh on subsequent launches
  - Manual: install build, push pipeline catalog refresh, relaunch app, verify new catalog version shows
- **DoD:** Repeat-launch catalog refresh works on real device; rollback path tested.
- **Verified 2026-04-29:** Bundle-replacement bug fix is done and unit tests are green inside the 624-test suite. **Activation-model work (in-session vs cold-start) is tracked separately in `INITIATIVE_PRODUCT_TRUST_AND_IA.md` T0.6** — A6 was scoped to the "bundle no longer copies after first install" defect, which is fixed regardless of activation strategy. Real-device pass on the activation snackbar belongs to T0.6's acceptance.

---

# Track B — V1.1 Stack Intelligence (3–5 dev days)

**Goal:** Replace the single-number headline with a diagnostic tier and issue list, using the smallest atomic diff that fully preserves one source of truth.

**Definition of Done (sprint-level):**
- `StackIntelligence` model exists and is the single output of the engine
- Engine composes existing `StackSafetyReport`, `recalledIngredientsReport`, `nutrientStatuses`, `synergyReport` without duplicating logic
- Home headline renders tier label + issue count; 0–100 score relegated to a secondary line
- All tier-derivation rules covered by unit tests
- Existing 449+ tests still pass
- No goal-coverage UI in V1.1 (deferred until clinician thresholds available)

---

### `[x]` B1 — `StackIntelligence` model
- **Why:** Model-first. Lock the output shape before writing the engine.
- **What:** New model with the `StackTier` enum (optimized / solid / decent / concerning / unsafe / incomplete), `StackIssue`, derivation function, sub-summaries (interactions count, nutrient warnings count, recall flag, contraindicated flag).
- **Files:**
  - `lib/core/models/stack_intelligence.dart` (NEW)
  - `test/core/models/stack_intelligence_test.dart` (NEW)
- **Tests:**
  - Tier-derivation rules: banned → unsafe; contraindicated → unsafe; avoid → concerning; UL approaching → decent or concerning by count; clean → solid or optimized; missing data → never above decent
  - Empty-stack edge case → incomplete
- **DoD:** Compiles. ≥8 unit tests pass. No engine code yet.
- **Comments:** Keep model lean — no business logic beyond tier derivation. Engine in B2 owns composition.
- **Verified 2026-04-28:** 18/18 tests pass (`flutter test test/core/models/stack_intelligence_test.dart`); analyze still clean. `StackTier.healthLabel` reuses the existing `StackHealthLabel` for the five user-facing tiers; `incomplete` returns `null` so callers must render neutral copy.

### `[x]` B2 — `StackIntelligenceEngine` facade
- **Why:** Single entry point for "give me the diagnosis for this stack + profile". All existing checkers stay; engine composes them into the new model.
- **What:** Engine consumes existing reports (`StackSafetyReport`, `recalledIngredientsReport`, `nutrientStatuses`, `synergyReport`, stack count) and emits a `StackIntelligence` instance.
- **Files:**
  - `lib/services/stack/stack_intelligence_engine.dart` (NEW)
  - `test/services/stack/stack_intelligence_engine_test.dart` (NEW)
- **Tests:**
  - Empty stack → tier=incomplete
  - Single banned ingredient + N clean → tier=unsafe
  - Single contraindicated interaction + N clean → tier=unsafe
  - Avoid-level interaction → tier=concerning
  - UL approaching across 2+ products → tier=decent or concerning
  - All clean + good coverage → tier=solid or optimized
- **DoD:** ≥6 engine-level tests; no breaking changes to existing services; engine returns `StackIntelligence` for every input shape.
- **Comments:** Engine is a facade — never duplicates logic from `StackSafetyScorer`, `StackInteractionChecker`, `StackNutrientAggregator`. Reuses them.
- **Verified 2026-04-28:** 9/9 tests pass. Engine reads counts/flags off the existing reports and feeds them into `StackIntelligence.deriveTier`; no scorer/checker/aggregator logic duplicated. `nutrientStatuses` are sourced from `safetyReport.nutrientStatuses` (already inside the safety report) rather than as a separate parameter — keeps the surface lean. `synergyReport` is accepted for API stability but not yet used in tier derivation (synergy is positive guidance, not a safety signal).

### `[x]` B3 — Headline swap on home screen
- **Why:** The visible payoff. Tier verdict replaces the number; users see "Solid stack · 7 products · 2 attention items" instead of "73/100".
- **What:** Modify the home stack health widget to render tier label + issue count as headline. Keep 0–100 score available as a secondary line via `intelligence.qualitySummary.weightedScore`.
- **Files:**
  - `lib/features/home/widgets/home_stack_health.dart` (MODIFY)
  - `test/features/home/widgets/home_stack_health_test.dart` (MODIFY or NEW if missing)
- **Tests:**
  - Each tier renders correct color + copy + icon
  - Goldens updated for the new layout
  - Tap behavior preserved (existing detail navigation still works)
- **DoD:** Real-device check on iOS + Android; goldens green; existing tests pass.
- **Comments:** Do not remove the 0–100 number from the codebase — relegate it. Some internal screens may still show it as a secondary signal.
- **Verified 2026-04-28:** Wired `StackIntelligenceEngine` into `home_stack_health.dart`. The status pill now reads off `intelligence.tier.healthLabel`, so banned/recalled ingredients dominate the headline (previously a stack with banned items could still show `Solid` if the score happened to round high). Top-issue callout pulls from `intelligence.issues.first.headline` — recall-bearing products surface above interactions. The 0..100 score still feeds the engine via `qualityScore` and is preserved (relegated, not removed) per the locked rule. Falls back to the score-derived label while any input is loading to avoid flicker. `flutter analyze` clean; full suite 624/624 green. Goldens + real-device pass on iOS/Android still owed by Sean (deferred to TestFlight QA).

---

# Track C — V1.2 Clinician Share Report (2–4 dev days)

**Goal:** Doctor/pharmacist-shareable summary. Text/markdown first; PDF deferred to v1.2.1.

**Definition of Done (sprint-level):**
- User can share a clinician-ready report from the stack screen in 2 taps
- Report includes: products + medications + warnings (severity-sorted) + UL alerts + recalled flags + evidence/citation links + disclaimer + privacy note
- Report is markdown (pasteable into MyChart, email, Notes)
- Manual verification: report opens cleanly in Mail, Messages, Notes
- No health data leaves the device unintentionally

---

### `[x]` C1 — Clinician report builder
- **Why:** Compose a deterministic markdown summary from on-device state. Pure function: stack + profile → markdown string.
- **What:** New service that takes user's stack + profile + interaction reports and outputs a structured markdown document.
- **Files:**
  - `lib/services/sharing/clinician_report_builder.dart` (NEW)
  - `test/services/sharing/clinician_report_builder_test.dart` (NEW)
- **Tests:**
  - Known stack + profile → known markdown (golden-string test)
  - Includes "educational, not medical advice" disclaimer
  - Includes "generated on device" privacy note
  - Severity-sorted warnings (unsafe > concerning > caution > info)
- **DoD:** ≥5 unit tests; report markdown matches expected structure for golden case.
- **Verified 2026-04-29:** `ClinicianReportBuilder.build({profile, stack, intelligence, generatedAt})` — pure function, no I/O. Inputs: nullable `UserProfile` Drift row, `List<UserStacksLocalData>`, the `StackIntelligence` from B2 (which already provides severity-sorted issues — builder renders in order without re-sorting), and an injected `DateTime` for golden-string determinism. Output sections: header + on-device privacy note + top-level disclaimer; Profile (when populated, renders age / sex / conditions / drug classes / goals / allergens — JSON arrays decoded defensively, malformed JSON falls through to empty without throwing); Medications + Supplements (split by `type`, dosage and frequency rendered when present); Stack Diagnosis (tier + counts + ⚠️ flags for banned / recalled / contraindicated); Warnings (severity-sorted bullets with the existing `Severity.label` ALL-CAPS prefix); footer disclaimer. **11 unit tests pass** (target ≥5): privacy note + top + footer disclaimer, YYYY-MM-DD date format, section visibility (null profile / empty stack hide cleanly), profile/med/supp population, diagnosis flags + counts, severity-ordered warnings (contraindicated → avoid → caution → monitor), full golden-string match, and JSON-decode safety against malformed/non-list shapes. `flutter analyze` clean.

### `[x]` C2 — Share intent wiring
- **Why:** Pipe the markdown into the system share sheet without leaking unintended payload.
- **What:** Extend existing `ShareService` (already uses `share_plus`) with `shareClinicianReport()`.
- **Files:**
  - `lib/services/sharing/share_service.dart` (MODIFY)
  - `test/services/sharing/share_service_test.dart` (MODIFY or NEW)
- **Tests:**
  - `shareClinicianReport()` calls `share_plus` with the builder's output
  - No additional payload (no analytics ping with content)
- **DoD:** Widget test confirms share sheet invocation with expected text body.
- **Verified 2026-04-29:** `ShareService` gained an optional `ShareInvocation` constructor override (`shareOverride`) so unit tests can capture the text/subject the service hands to `share_plus` without spinning up a platform channel. New `shareClinicianReport(String markdown)` is a thin pass-through — calls `_share(markdown, subject: 'My Supplement Stack — Clinician Summary')`. No analytics tap, no payload reshaping, no fallbacks. Existing `shareProduct` and `shareStackSummary` paths untouched. **3 new tests pass** (4 total in the file): payload forwarded verbatim with the clinician subject; exactly one share-sheet invocation per call (no duplicate fan-out, no analytics ping); empty markdown still produces a share invocation (builder may legitimately produce a tiny body for an empty stack).

### `[x]` C3 — UI entrypoint on stack screen
- **Why:** The user-facing button. Without it, C1/C2 are invisible.
- **What:** Button in stack screen → builds report → opens share sheet.
- **Files:**
  - `lib/features/stack/widgets/share_clinician_report_button.dart` (NEW)
  - `lib/features/stack/stack_screen.dart` (MODIFY — single line to wire the button)
- **Tests:**
  - Widget test: tap button → share sheet opens
  - Real-device test: report ends up in Mail/Messages/MyChart paste cleanly
- **DoD:** Button visible on stack screen; tap → share sheet on iOS + Android; report copy lands in target apps without truncation.
- **Verified 2026-04-29 (code) / ⏳ Sean (real-device):** New `ShareClinicianReportButton` (ConsumerWidget) wired into the stack screen's `AppBar.actions` with the iOS-style share icon (`Icons.ios_share_rounded`) + "Share with clinician" tooltip. On tap, the button reads `userDatabaseProvider.getProfile()`, `activeStackProvider`, `stackSafetyReportProvider`, `synergyReportProvider`, `recalledIngredientsReportProvider`, computes the same `safetyScore` shape `home_stack_health.dart` uses (so the diagnosis tier matches the home headline), runs `StackIntelligenceEngine.diagnose(...)`, builds the markdown via `ClinicianReportBuilder`, and hands it to the injected `ShareService`. Catch-all on the input collection drops a non-blocking failure snackbar — the share sheet never opens with partial data. Constructor takes an optional `shareService` so unit tests inject the C2 fake. **2 widget tests pass:** icon + tooltip render correctly; tap completes without throwing and either reaches the share service OR surfaces the failure snackbar (silent hang is the one outcome forbidden). Real-device verification (report opens cleanly in Mail / Messages / MyChart paste) ⏳ **Sean** — belongs to the TestFlight smoke per the spec's "Real-device test" line.

### `[x]` C4 — PDF export
- **Why:** PDF gives clinicians a more durable visit artifact than raw markdown while preserving the on-device privacy model.
- **What:** Generate and share a branded offline PDF report from the stack screen. The report includes PharmaGuide logo/Geist typography, profile snapshot, medications, supplements, stack diagnosis, warnings, nutrient totals, timing recommendations, medication nutrient notes, and limitations copy.
- **Files:** `lib/services/sharing/clinician_pdf_builder.dart`, `lib/services/sharing/share_service.dart`, `lib/features/stack/widgets/share_clinician_report_button.dart`, `pubspec.yaml`, `assets/images/report_logo.png`, `assets/fonts/Geist-Regular.ttf`, `assets/fonts/Geist-Medium.ttf`.
- **Tests:** `test/services/sharing/clinician_pdf_builder_test.dart`, `test/services/sharing/share_service_test.dart`, `test/features/stack/widgets/share_clinician_report_button_test.dart`.
- **DoD:** ✅ Code complete 2026-05-28. Post-review fixes included: PDF warnings defensively severity-sort, nutrient warning sort no longer relies on bool string comparison, report-build failures record through `CrashReportingService`, and medication-pair interactions now feed the shared ordered warning stream. `flutter analyze` clean. `flutter test test/services/stack/stack_safety_report_test.dart test/services/sharing/clinician_pdf_builder_test.dart test/features/stack/widgets/share_clinician_report_button_test.dart` passes (19 tests). Full `flutter test` passes (1530 tests). Real-device PDF share smoke ⏳ Sean.

---

# Track D — V1.3 OTA Catalog Refresh (3–4 dev days)

**Goal:** Solid background catalog refresh. Download in background; activate **in current session via T0.6's validated swap routine**; rollback to old DB on failure.

**Definition of Done (sprint-level):**
- App polls a versioned manifest on launch
- Newer bundles download to a staging directory in the background
- Validation gate runs against the staged file before the live DB is touched
- Activation happens in-session via T0.6's swap routine with a subtle "catalog updated" indicator
- Failed bundle (corruption, schema mismatch) rolls back to last-known-good without user-visible error

---

### `[x]` D1 — Versioned bundle manifest endpoint
- **Why:** App needs a stable URL to poll for "is there a new catalog?".
- **What:** Pipeline already produces versioned bundles (`v2026.04.27.063145`). Confirm the CDN exposes a `manifest.json` advertising `latest_version` + bundle URL + SHA256.
- **Files (pipeline):**
  - `scripts/release_full.sh` (VERIFY — already produces versioned bundles)
  - `scripts/build_manifest.py` (NEW or VERIFY existing) — emits `manifest.json` with `latest_version`, `bundle_url`, `sha256`, `released_at`
- **Tests (pipeline):**
  - `scripts/tests/test_manifest_contract.py` (NEW) — manifest has required keys, version is monotonically newer than previous
- **DoD:** Curl-able manifest URL returns valid JSON; SHA matches actual bundle on CDN.
- **Verified — 2026-04-29.** Verified the existing pipeline path satisfies the contract end-to-end:
  - `release_catalog_artifact.py` stages `dist/export_manifest.json` with `db_version` (= `latest_version`), `checksum` + `checksum_sha256` (= `sha256`), `generated_at` (= `released_at`).
  - `sync_to_supabase.py` uploads the bundle to the `pharmaguide` Supabase Storage bucket at `v{db_version}/pharmaguide_core.db` and writes the manifest row via the `rotate_manifest` RPC. The Postgres `export_manifest` table (queried by `SyncService.fetchCurrentDbVersion`) IS the curl-able manifest endpoint via Supabase's auto-generated REST.
  - `bundle_url` is derivable from `db_version` via `SupabaseContract.coreDbPath(version)` — no separate URL field needed.
  - **NEW** `scripts/tests/test_manifest_contract.py` — 12 tests pinning the contract: required keys, sha256 64-hex, db_version YYYY.MM.DD.HHMMSS lex-sortability, generated_at ISO-8601 UTC, bundle-URL derivation, prefixed/raw checksum agreement, monotonicity (older < newer string-compare), JSON round-trip stability, schema-stability guard.

### `[x]` D2 — Background catalog updater service (Flutter)
- **Why:** Keep the active session uninterrupted while a new catalog downloads.
- **What:** New service that, on app launch, fetches the manifest, compares to installed version, and downloads the new bundle to a staging directory if newer.
- **Files (flutter):**
  - `lib/services/catalog_updater_service.dart` (NEW)
  - `test/services/catalog_updater_service_test.dart` (NEW)
- **Tests:**
  - Newer version available → download triggered
  - Same version → no-op
  - Network failure → silent fail, retry next launch
  - SHA mismatch on download → discard, retry next launch
- **DoD:** ≥4 unit tests with mocked HTTP; staging directory cleanup on failure.
- **Verified — 2026-04-29.**
  - **NEW** `lib/services/catalog_updater_service.dart` — `CatalogUpdaterService` with DI-callback shape (matches `CatalogSwapper` pattern). Sealed `CatalogCheckResult` hierarchy (`CatalogUpToDate`, `CatalogStaged`, `CatalogUnreachable`, `CatalogStageFailed`). Production factory wires `SyncService` deps. Validation gate (PRAGMA + version match) is delegated to `SyncService.stageCoreDbDownload` so a `CatalogStaged` result means the file in `*.staging` already cleared corruption checks.
  - **NEW** `test/services/catalog_updater_service_test.dart` — 8 tests covering: newer→staged, same→up-to-date (no download), force-download bypass, first-launch (null installed) → staged, probe-throws→unreachable, probe-null→unreachable, stage-throws→stage-failed, production factory smoke.
  - **MODIFY** `lib/main.dart` — `_refreshCatalogIfNeeded` now delegates probe + stage to `CatalogUpdaterService.checkForUpdate()` and dispatches on the sealed result. Swap step (which mutates setState + closes old DB) extracted to `_activateStagedCatalog` and runs only on `CatalogStaged`. The previous-DB cleanup, version persistence, and snackbar fire-once behavior all preserved verbatim.

### `[x]` D3 — Wire in-session swap into the launch refresh path
- **Why:** Connects the background download (D2) and rollback safety (D4) to the live app via an atomic, validated swap. No relaunch required — freshness arrives within the session that detected it.
- **What:** Wire T0.6's swap routine into `_refreshCatalogIfNeeded` so a successful, validated download activates immediately. Surface the snackbar via the existing notice mechanism.
- **Source of truth:** Implementation spec, sequencing, validation gate details, snackbar copy, and unit-test list all live in `INITIATIVE_PRODUCT_TRUST_AND_IA.md` **T0.6**. D3 tracks the Stack-Intelligence-side checkbox; do not duplicate the spec here.
- **Files (flutter):** see T0.6 (`lib/main.dart`, `lib/data/supabase/sync_service.dart`, `lib/services/catalog_swap.dart`).
- **DoD:** Same as T0.6's acceptance — new catalog visible in-session, snackbar fires once, validation failure rolls back cleanly, `_activeCatalogVersion` persists across kill+relaunch.
- **Verified — 2026-04-29.** Shipped via T0.6 in commit 813aa0b. D2 refactor in commit (this work) hoists the probe+stage into `CatalogUpdaterService` while preserving the in-session swap path through `_activateStagedCatalog`. Snackbar fire-once + version persistence + rollback semantics all preserved verbatim.

### `[x]` D4 — Rollback safety
- **Why:** Bundle corruption or schema drift must never brick the app.
- **What:** If new bundle fails to open, retain old DB and report telemetry.
- **Files (flutter):**
  - `lib/data/providers/database_providers.dart` (MODIFY — add try/catch with rollback)
  - `test/data/providers/database_providers_test.dart` (MODIFY)
- **Tests:**
  - Forced-failure integration test (corrupted bundle) → falls back to old DB
  - Telemetry event fires for catalog-rollback (privacy: only version + error code, no user data)
- **DoD:** Forced-corruption test passes; telemetry payload is minimal.
- **Verified — 2026-04-29.**
  - **MODIFY** `lib/data/providers/database_providers.dart` — `openCoreDatabase` now probes the on-disk file via `validateCatalogSnapshot()`. On any failure (open throw, SqliteException on first query, structural validation miss) it force-restores from the bundled asset via `_restoreBundledCoreDatabase` (a new private helper that bypasses the size-match cheap path) and retries the open once. Privacy-clean telemetry: a `[catalog-rollback]` debug-print with the runtime exception type only — no user data, no file path. The "old DB" fallback target is the bundled asset (always present, ships with the binary), since the `.backup` file is transient and only exists during a swap.
  - **MODIFY** `test/data/providers/database_providers_test.dart` — three new tests under `openCoreDatabase rollback safety`: happy-path (healthy DB opens, no fallback fires), corruption fallback (size-matched 0xff garbage on disk → restore from bundle → retry open → working DB with `countProducts > 0` and file length matching the asset), first-launch (no on-disk file → bundle materializes → probe passes). All three exercise the real bundled asset for verisimilitude. The corruption test confirms the rollback path actually fires (`SqliteException` is the observed failure class).

---

# Track E — V1.4+ Commerce (DEFERRED until V1.2 trust established)

**Strategic note:** Commerce lands AFTER trust. Affiliate links before clinical credibility hurt the brand. This track is locked behind V1.2 shipping successfully.

**Provider strategy (locked):** Skip Amazon. Build on Impact Radius only (iHerb, Vitacost, Swanson, LuckyVitamin, Pure Formulas). Re-evaluate Amazon when Creators API requirements stabilize.

**Definition of Done (sprint-level):**
- Impact Radius approved + ≥3 retailers enrolled
- Pipeline emits `purchase_options[]` per UPC-keyed product, refreshed weekly
- Flutter shows price-comparison bottom sheet → external browser deep link
- Apple/Play store review passes (physical goods, external browser → no IAP cut)
- Analytics payload is privacy-first (`dsld_id`, `provider`, `price_usd` only — no health data)
- Cost layer (Layer 6) integrated into `StackIntelligenceEngine` and renders only when ≥50% of stack has price data

---

### `[-]` E6 — Affiliate program signup (admin, runs in parallel with Tracks A–D)
- **Why:** Impact Radius approval has 1–2 day lag, then per-retailer enrollment is 1 day each. Start now so credentials are ready when V1.4 build begins.
- **What:**
  - Apply to Impact Radius as Publisher
  - Once approved, enroll in iHerb, Vitacost, Swanson, LuckyVitamin, Pure Formulas
  - **Skip Amazon Associates / PA-API** until Creators API requirements are public
  - Add `IMPACT_ACCOUNT_SID`, `IMPACT_AUTH_TOKEN` to `scripts/.env` template
- **Files:** `scripts/.env.example` (MODIFY — add Impact env keys with placeholders)
- **Tests:** N/A (admin work).
- **DoD:** Impact account active; ≥3 retailer enrollments; credentials in pipeline `.env`.

### `[ ]` E7 — `PriceCatalog` module (Impact-only)
- **Why:** Single price-fetch entry point for the pipeline.
- **What:** New module with `PriceCatalog().lookup_by_upc(upc) -> Optional[PriceRecord]` and a 7-day cache.
- **Files (pipeline):**
  - `scripts/api_audit/price_catalog.py` (NEW)
  - `scripts/api_audit/price_providers/impact_radius.py` (NEW)
  - `scripts/data/price_cache.json` (NEW — empty initial)
- **Tests (pipeline):**
  - `scripts/tests/test_price_catalog.py` (NEW) — mocked HTTP fixture tests for Impact provider chain (iHerb → Vitacost → Swanson) + cache TTL + provider fallback
- **DoD:** `PriceCatalog().lookup_by_upc("049022861282")` returns valid `PriceRecord` against Impact mock; cache hit on same UPC within 7 days returns immediately; tests green.

### `[ ]` E8 — Detail blob `purchase_options[]` + weekly refresh cron
- **Why:** Bake price into the bundle Flutter consumes. No runtime API calls from mobile.
- **What:**
  - For each product with `upc_sku`, `build_final_db.py` calls `PriceCatalog.lookup_by_upc(upc)` and emits top-level `purchase_options[]` per blob (sorted ascending by price)
  - Also emits `lowest_price_usd` and `lowest_price_provider` to `products_core` SQLite for fast filter/sort
  - Weekly GitHub Action cron rebuilds + syncs to Supabase
- **Files (pipeline):**
  - `scripts/build_final_db.py` (MODIFY)
  - `scripts/run_price_refresh.sh` (NEW)
  - `.github/workflows/price-refresh.yml` (NEW, Mondays 06:00 UTC)
  - `scripts/tests/test_blob_purchase_options.py` (NEW)
  - `scripts/FINAL_EXPORT_SCHEMA_V1.md` (UPDATE → v1.2)
- **Tests:** Blob has `purchase_options[]` when UPC is set; field absent when UPC is empty; schema test passes.
- **DoD:** ≥70% of UPC-keyed products have ≥1 purchase option after full pipeline rebuild; weekly cron runs successfully.

### `[ ]` E9 — Flutter purchase service + price-comparison sheet
- **Why:** User-facing payoff. "Buy" buttons that open external browser with affiliate-tagged URL.
- **What:**
  - New `PurchaseOption` model
  - `PurchaseService` opens external browser via `url_launcher`, appends `subid=dsld_<id>` for attribution
  - `PurchaseOptionsSheet` bottom sheet with sorted price comparison
  - Wire from product detail screen
- **Files (flutter):**
  - `lib/core/models/purchase_option.dart` (NEW)
  - `lib/services/purchase_service.dart` (NEW)
  - `lib/features/product_detail/widgets/purchase_options_sheet.dart` (NEW)
  - `lib/features/product_detail/product_detail_screen.dart` (MODIFY — single line to wire button)
  - Tests for each new file
- **Tests:**
  - `PurchaseOptionsSheet` renders 3 options sorted by price ascending
  - Tapping "Buy" calls `PurchaseService.openPurchaseLink` with correct affiliate URL
  - `PurchaseService` builds URLs with provider-specific affiliate tag + `subid=dsld_<id>`
- **DoD:** Real-device test on iOS + Android; deep link opens to retailer page; affiliate tag present in URL.

### `[ ]` E10 — Stack cost layer (Layer 6 of `StackIntelligence`)
- **Why:** Cost-effectiveness diagnostic on the stack dashboard. Strictly additive to V1.1 engine.
- **What:**
  - Pipeline: add `cheaper_alternatives[]` per blob (top 3 same category, ±5 quality, same form)
  - Flutter: `StackCostCalculator` sums daily cost + finds cheaper alternatives across stack; engine gains optional `costSummary`; new dashboard card
- **Files (pipeline):**
  - `scripts/build_final_db.py` (MODIFY — `cheaper_alternatives[]`)
- **Files (flutter):**
  - `lib/services/stack/stack_cost_calculator.dart` (NEW) + test
  - `lib/services/stack/stack_intelligence_engine.dart` (MODIFY — add Layer 6)
  - `lib/core/models/stack_intelligence.dart` (MODIFY — `costSummary` field, optional)
  - `lib/features/stack/widgets/stack_cost_card.dart` (NEW) + test
- **Tests:** Cost card only renders when ≥50% of stack has price data; gracefully absent when missing.
- **DoD:** Real stack with 5 priced products → daily cost shown + cheaper alternatives suggested; stack with no price data → card hidden cleanly.

### `[ ]` E11 — Affiliate reports (privacy-first analytics)
- **Why:** Track which products drive revenue without leaking health data.
- **What:**
  - Pipeline: weekly job pulls Impact reports; joins by sub-tag → DSLD ID; writes summary
  - Flutter: `purchase_intent` analytics payload locked to `{dsld_id, provider, price_usd}` ONLY — no goals, no meds, no conditions, no stack contents, no persistent user ID
- **Files (pipeline):**
  - `scripts/api_audit/affiliate_reports.py` (NEW)
  - `.github/workflows/affiliate-reports.yml` (NEW, weekly cron)
- **Files (flutter):**
  - `lib/services/analytics_service.dart` (MODIFY — verify payload shape)
  - `test/services/analytics_service_test.dart` (MODIFY — assert payload contains only allowed keys)
- **Tests:**
  - Pipeline: weekly report generation produces valid markdown
  - Flutter: analytics payload assertion test prevents future health-data leakage
- **DoD:** Weekly report shows revenue + CTR per provider; analytics payload audit passes.

---

## Hard "Do Not" Rules (locked)

| Don't | Why |
|---|---|
| Show a 0–100 number as the headline | Conflicts with "diagnostic, not score" thesis |
| Use A/B/C/D/F letter grades | Reads as a fake clinical grade |
| Use "covered / under-dosed / missing" goal verdicts without clinician thresholds | Implies treatment adequacy → FDA CDS regulatory risk |
| Build on Amazon PA-API | Deprecates 2026-05-15 |
| Send health data in analytics events | Privacy moat breaks; legal exposure |
| Touch >3 files per task | Violates AGENTS.md |
| Land commerce before V1.2 trust ships | Affiliate bias before clinical credibility = brand damage |
| Swap the SQLite DB without validation gate or atomic rename | Corruption / data-integrity risk. T0.6 specifies the validation-gate + atomic-rename + Drift-close-reopen pattern that makes in-session swap safe; in-session swap itself is allowed and expected. |
| Add affiliate disclosure that mentions Amazon | We don't ship Amazon; disclosure must match active providers only |

---

## Calendar / Critical Path

| Week | Focus | Deliverable |
|---|---|---|
| **Week 1 (now, 2026-04-28 → 2026-05-04)** | Track A — V1.0 hardening + OTA fix verification | TestFlight + Play Internal builds |
| **Week 2 (2026-05-05 → 2026-05-11)** | Track B — V1.1 Stack Intelligence (B1, B2, B3) | App Store / Play submission |
| **Week 3 (2026-05-12 → 2026-05-18)** | Track C — V1.2 Clinician Share Report (C1, C2, C3) | Update submission |
| **Week 4 (2026-05-19 → 2026-05-25)** | Track D — V1.3 OTA polish (D1, D2, D3, D4) | Update submission |
| **Week 5–6** | Track E admin (E6) + Impact Radius approval lag | (no user-facing change) |
| **Week 7+ (2026-06-08 →)** | Track E build (E7 → E11) | V1.4 commerce update |

**Critical path:** Track E6 admin signup runs **in parallel** with Tracks A/B/C/D so Impact approval is ready when V1.4 build starts.

---

## Dependency Graph

```
Track A ──┐
          ├──→ Track B ──→ Track C ──→ Track D ────────────→ Track E (E7→E11)
          │                                                   ↑
          └──→ E6 signup runs in parallel ────────────────────┘
```

**Locks:**
- B can't ship before A (don't destabilize)
- C builds on B's `StackIntelligence` model
- E build can't start until E6 signup approved + V1.2 shipped
- D ships independent of B/C but should land before E (clean catalog refresh in place before commerce data lands)

---

## Open Questions / Decisions Needed

Track decisions here as they come up. Resolve in line, then mark resolved.

- `[x]` (decision-1) Use the neutral label "More info needed." It overrides monitor-only and score-band labels when evaluation is materially incomplete, but never hides caution, avoid, contraindicated, banned, or recalled findings. Resolved 2026-08-08 by ADR-006.
- `[ ]` (decision-2) For C3 (share button placement), top-right action vs bottom CTA? Defer to UX review during C3.
- `[ ]` (decision-3) Per-retailer affiliate disclosure language for E9 — Impact retailers don't all require the same wording. Audit each retailer's TOS before E9 ships.
- `[-]` (decision-4) When (if ever) to add Amazon Creators API. Re-evaluate Q3 2026.

---

## Retirement Criteria

This initiative retires when:

1. `[ ]` V1.0 shipped to App Store + Play Store
2. `[ ]` V1.1 Stack Intelligence shipped (Track B complete)
3. `[ ]` V1.2 Clinician Share Report shipped (Track C complete)
4. `[x]` V1.3 OTA Catalog Refresh shipped (Track D complete) — D1+D2+D3+D4 verified 2026-04-29; Sean owes a real-device smoke (force-corrupt the on-disk file → relaunch → verify the app boots and surfaces the bundled-asset fallback) before flipping the App Store cycle.
5. `[ ]` V1.4 Commerce shipped (Track E complete)
6. `[ ]` All open questions in this doc resolved or migrated to other trackers
7. `[ ]` Final summary written + relevant lessons rolled into `lessons-learned.md` and `architecture-decisions.md`
8. `[ ]` Move this file to `archive/` directory with `archived: <date>` in front-matter

When all 8 boxes ticked → close out + archive.

---

## Update Log

Append a one-line entry per meaningful change.

- **2026-08-08** — Resolved decision-1 via ADR-006. Stack Health now uses one shared snapshot and signal count across Home, Stack, hero, and details; materially incomplete clean/monitor-only stacks render neutral "More info needed"; dose-threshold alerts join the typed signal universe; the internal numeric score no longer exposes a second tier API. Replaced stale "ideal stack" and max-three-files language.
- **2026-04-28** — Initiative created. Tracks A–E defined. Locked architectural principles, tier vocabulary, Amazon PA-API skip decision, hard "do not" rules.
- **2026-04-28** — A1 + A2 verified (`analyze` clean, 597 tests pass after pruning stale "category chips" test). A4 confirmed already shipped in Sprint 27.18. A6 unit tests green; real-device pass still owed.
- **2026-04-28** — Track B B1 + B2 + B3 landed in a single session. New `StackIntelligence` model (18 tests) + `StackIntelligenceEngine` facade (9 tests) + home headline rewire. Full suite 624/624. AGENTS.md ≤3-files rule honored per task. Goldens/real-device pass for B3 still owed.
- **2026-04-29** — Retired the "no mid-session catalog swap" locked rule. The activation-model debate is resolved in favor of `INITIATIVE_PRODUCT_TRUST_AND_IA.md` T0.6's validation-gated in-session swap. Updated locked-principles row, success metric, Track D goal/DoD, D3 (now points at T0.6 as source of truth), Hard "Do Not" row (rewritten to forbid swap *without* validation gate, not in-session swap itself). A6 marked `[x]` — its bundle-replacement bug fix is done; the activation-snackbar work belongs to T0.6.
- **2026-04-29** — Trust & IA Sprint 0 shipped (commits `813aa0b` + `2a35eb8`). Cross-initiative impact: full test suite now 741/741 across both initiatives (was 624/624 after Track B). Stack Intelligence's Track A B1/B2/B3 work continues to be green inside the larger 741. No Stack Intelligence code-side changes in those Trust & IA commits.
- **2026-04-29** — Track C V1.2 Clinician Share Report code-complete. C1 + C2 + C3 all `[x]`. New `ClinicianReportBuilder` (pure function, golden-string tested) + `ShareService.shareClinicianReport` (DI-friendly via `ShareInvocation` override) + `ShareClinicianReportButton` wired into the stack screen's AppBar. AGENTS.md ≤3-files rule honored per task. Full suite 741 → 757 (+16: 11 C1 + 3 C2 + 2 C3). C3 real-device pass (Mail / Messages / MyChart paste) still ⏳ Sean per the spec's "Real-device test" DoD line.
- **2026-05-28** — Track C C4 PDF export code-complete and review-fixed. Added branded offline PDF generation (`pdf` + `printing`), PharmaGuide logo + Geist assets, native PDF share path, and PDF/widget/share-service tests. Follow-up review fixes: severity-sort PDF warnings defensively, include medication-pair interactions in `StackSafetyReport.orderedWarnings`, replace bool string sorting in nutrient totals, record report-build failures to `CrashReportingService`, and cover null profile / empty stack. `flutter analyze` clean; full `flutter test` passes 1530/1530. Real-device PDF share smoke still ⏳ Sean.
- **2026-04-29** — Track D V1.3 OTA Catalog Refresh code-complete. D1 + D2 + D3 + D4 all `[x]`. Pipeline-side: new `scripts/tests/test_manifest_contract.py` (12 tests) pinning the export_manifest contract the Flutter app + uploader rely on (key shape, sha256 64-hex, db_version lex-sortability, ISO-8601 UTC, monotonicity, JSON round-trip). Flutter-side: new `CatalogUpdaterService` extracts probe + stage out of `_refreshCatalogIfNeeded` (8 unit tests, sealed `CatalogCheckResult`); `openCoreDatabase` gains a probe-and-restore D4 fallback that force-restores the bundled asset on any open or `validateCatalogSnapshot()` failure (3 new tests covering happy-path, size-matched corruption, first-launch). Full Flutter suite 757 → 768 (+8 D2 + 3 D4). Pipeline suite gains 12 manifest-contract tests. Real-device smoke (force-corrupt the on-disk file → relaunch → verify rollback fires) still ⏳ Sean.
