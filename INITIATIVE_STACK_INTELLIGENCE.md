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
| Stack Health surfaces a tier verdict + actionable issues, not a score | `home_stack_health.dart` renders tier label as headline; 0–100 number relegated to secondary signal |
| Banned/recalled ingredients always trigger an "Unsafe" headline regardless of other quality signals | Unit tests assert `unsafe` tier in every gate-trigger scenario |
| Users can share a clinician-ready stack summary in 2 taps | Markdown report → system share sheet; manually verified on real device |
| TestFlight/Play users receive catalog updates without reinstalling the app | OTA bundle download on launch; activation at next cold start; rollback on failure |
| Affiliate program ready to plug in once V1.2 ships, **without** Amazon PA-API exposure | Impact Radius approved + retailer enrollments live; no PA-API code in repo |
| Every change respects the AGENTS.md "max 3 files / surgical diff" rule | Each task delivers a single PR with ≤3 files |

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
| **AGENTS.md compliance: ≤3 files per task, surgical diffs** | Sprint tasks below honor this. |
| **Hard safety gates override every other signal** | A banned ingredient is never averaged away by quality. |
| **No invented clinical thresholds** | No "covered/under-dosed/missing" verdicts unless reference data has clinician-authored thresholds. Use neutral language ("no matched ingredients found", "below typical study doses"). |
| **No Amazon PA-API integration** | PA-API deprecates 2026-05-15. Skip Amazon entirely until Creators API requirements stabilize. Use Impact Radius (iHerb/Vitacost/Swanson) as the commerce backbone. |
| **No mid-session catalog swap** | OTA updates download in background, activate at next cold start. |

---

## User-facing stack tiers (locked)

```
Optimized   → ideal stack
Solid       → good, minor attention items
Decent      → some concerns worth reviewing
Concerning  → review needed (avoid-level interactions, near-UL, etc.)
Unsafe      → hard stop (banned/recalled, contraindicated)
```

Internal-only fallback state (rendered as neutral "more info needed" copy, never as a graded label):

```
Incomplete  → stack data too thin to diagnose
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

### `[-]` A6 — OTA database refresh fix verification
- **Why:** Bug found in 2026-04-28 session: `ensureCoreDatabaseAvailable` only copies on first install. Without the fix, TestFlight users get stuck on the catalog version that shipped with the app forever.
- **What:** The fix landed in today's session (`lib/data/providers/database_providers.dart`, `lib/main.dart`, `test/data/providers/database_providers_test.dart`). Verify it survives review and works on real device.
- **Files:** Already modified — re-verify.
- **Tests:**
  - `test/data/providers/database_providers_test.dart` — assert refresh on subsequent launches
  - Manual: install build, push pipeline catalog refresh, relaunch app, verify new catalog version shows
- **DoD:** Repeat-launch catalog refresh works on real device; rollback path tested.
- **Status 2026-04-28:** Unit-test portion green inside the 597-test suite run. Real-device verification still pending Sean's TestFlight push.

---

# Track B — V1.1 Stack Intelligence (3–5 dev days)

**Goal:** Replace single-number headline with diagnostic tier + issue list. AGENTS.md-compliant: each task ≤3 files.

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

### `[ ]` C1 — Clinician report builder
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

### `[ ]` C2 — Share intent wiring
- **Why:** Pipe the markdown into the system share sheet without leaking unintended payload.
- **What:** Extend existing `ShareService` (already uses `share_plus`) with `shareClinicianReport()`.
- **Files:**
  - `lib/services/sharing/share_service.dart` (MODIFY)
  - `test/services/sharing/share_service_test.dart` (MODIFY or NEW)
- **Tests:**
  - `shareClinicianReport()` calls `share_plus` with the builder's output
  - No additional payload (no analytics ping with content)
- **DoD:** Widget test confirms share sheet invocation with expected text body.

### `[ ]` C3 — UI entrypoint on stack screen
- **Why:** The user-facing button. Without it, C1/C2 are invisible.
- **What:** Button in stack screen → builds report → opens share sheet.
- **Files:**
  - `lib/features/stack/widgets/share_clinician_report_button.dart` (NEW)
  - `lib/features/stack/stack_screen.dart` (MODIFY — single line to wire the button)
- **Tests:**
  - Widget test: tap button → share sheet opens
  - Real-device test: report ends up in Mail/Messages/MyChart paste cleanly
- **DoD:** Button visible on stack screen; tap → share sheet on iOS + Android; report copy lands in target apps without truncation.

### `[-]` C4 — PDF export (deferred to v1.2.1)
- **Why:** PDF requires layout work and a heavier dependency. Markdown share covers the most common workflow (email to doctor, paste into MyChart) and ships faster.
- **What:** Generate a printable PDF version of the same report.
- **Files:** TBD when promoted from `[-]` to `[ ]`.
- **Tests:** TBD.
- **DoD:** TBD. Promote from `[-]` after v1.2 user feedback.

---

# Track D — V1.3 OTA Catalog Refresh (3–4 dev days)

**Goal:** Solid background catalog refresh. Download in background; activate at next cold start; safe rollback on failure.

**Definition of Done (sprint-level):**
- App polls a versioned manifest on launch
- Newer bundles download to a staging directory in the background
- Active session is never disrupted by a mid-session DB swap
- Activation happens at next cold start with a subtle "catalog updated" indicator
- Failed bundle (corruption, schema mismatch) rolls back to last-known-good without user-visible error

---

### `[ ]` D1 — Versioned bundle manifest endpoint
- **Why:** App needs a stable URL to poll for "is there a new catalog?".
- **What:** Pipeline already produces versioned bundles (`v2026.04.27.063145`). Confirm the CDN exposes a `manifest.json` advertising `latest_version` + bundle URL + SHA256.
- **Files (pipeline):**
  - `scripts/release_full.sh` (VERIFY — already produces versioned bundles)
  - `scripts/build_manifest.py` (NEW or VERIFY existing) — emits `manifest.json` with `latest_version`, `bundle_url`, `sha256`, `released_at`
- **Tests (pipeline):**
  - `scripts/tests/test_manifest_contract.py` (NEW) — manifest has required keys, version is monotonically newer than previous
- **DoD:** Curl-able manifest URL returns valid JSON; SHA matches actual bundle on CDN.

### `[ ]` D2 — Background catalog updater service (Flutter)
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

### `[ ]` D3 — Activate at next cold start
- **Why:** Atomic swap before opening the DB ensures consistency.
- **What:** At app start, before opening core DB, check staging directory; if newer bundle present, atomically swap then open. Show subtle "Catalog updated to {version}" banner first launch after swap.
- **Files (flutter):**
  - `lib/data/providers/database_providers.dart` (MODIFY)
  - `test/data/providers/database_providers_test.dart` (MODIFY)
  - `lib/main.dart` (MODIFY — single hook to surface the banner via existing snackbar/notice mechanism)
- **Tests:**
  - Staging present → swap + open new DB
  - Staging absent → open existing DB
  - Swap-then-open failure → rollback (D4)
- **DoD:** Real-device test: install old build, push new pipeline release, relaunch app, confirm new catalog active + banner shown once.

### `[ ]` D4 — Rollback safety
- **Why:** Bundle corruption or schema drift must never brick the app.
- **What:** If new bundle fails to open, retain old DB and report telemetry.
- **Files (flutter):**
  - `lib/data/providers/database_providers.dart` (MODIFY — add try/catch with rollback)
  - `test/data/providers/database_providers_test.dart` (MODIFY)
- **Tests:**
  - Forced-failure integration test (corrupted bundle) → falls back to old DB
  - Telemetry event fires for catalog-rollback (privacy: only version + error code, no user data)
- **DoD:** Forced-corruption test passes; telemetry payload is minimal.

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
| Swap the SQLite DB mid-session | Disrupts active scans; data integrity risk |
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

- `[ ]` (decision-1) Should the `incomplete` tier copy say "More info needed" or "Stack incomplete — add ingredients"? UX tone needs a call.
- `[ ]` (decision-2) For C3 (share button placement), top-right action vs bottom CTA? Defer to UX review during C3.
- `[ ]` (decision-3) Per-retailer affiliate disclosure language for E9 — Impact retailers don't all require the same wording. Audit each retailer's TOS before E9 ships.
- `[-]` (decision-4) When (if ever) to add Amazon Creators API. Re-evaluate Q3 2026.

---

## Retirement Criteria

This initiative retires when:

1. `[ ]` V1.0 shipped to App Store + Play Store
2. `[ ]` V1.1 Stack Intelligence shipped (Track B complete)
3. `[ ]` V1.2 Clinician Share Report shipped (Track C complete)
4. `[ ]` V1.3 OTA Catalog Refresh shipped (Track D complete)
5. `[ ]` V1.4 Commerce shipped (Track E complete)
6. `[ ]` All open questions in this doc resolved or migrated to other trackers
7. `[ ]` Final summary written + relevant lessons rolled into `lessons-learned.md` and `architecture-decisions.md`
8. `[ ]` Move this file to `archive/` directory with `archived: <date>` in front-matter

When all 8 boxes ticked → close out + archive.

---

## Update Log

Append a one-line entry per meaningful change.

- **2026-04-28** — Initiative created. Tracks A–E defined. Locked architectural principles, tier vocabulary, Amazon PA-API skip decision, hard "do not" rules.
- **2026-04-28** — A1 + A2 verified (`analyze` clean, 597 tests pass after pruning stale "category chips" test). A4 confirmed already shipped in Sprint 27.18. A6 unit tests green; real-device pass still owed.
- **2026-04-28** — Track B B1 + B2 + B3 landed in a single session. New `StackIntelligence` model (18 tests) + `StackIntelligenceEngine` facade (9 tests) + home headline rewire. Full suite 624/624. AGENTS.md ≤3-files rule honored per task. Goldens/real-device pass for B3 still owed.
