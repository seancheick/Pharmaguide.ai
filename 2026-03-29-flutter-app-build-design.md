# PharmaGuide Flutter App — Build Design

**Version:** 1.0.1
**Date:** 2026-04-02
**Source of truth:** PharmaGuide Flutter MVP Spec v5.3 (33 pages, frozen)
**Repo:** PharmaGuide_ai (new repo, greenfield)
**Builder:** Owner with Claude Code (new to Flutter)
**Platform:** iOS first (TestFlight), same code runs on Android

---

## Context

The PharmaGuide data pipeline (dsld_clean repo) is complete:

- 3-stage pipeline: Clean -> Enrich -> Score -> Build -> Sync
- The current distribution architecture targets the full `products_core` export (~180K products in `pharmaguide_core.db`). Live Supabase seed counts may be smaller during staged rollout/testing.
- Supabase v2.0.0 schema live: 4 tables, 2 RPCs, RLS, storage bucket
- All data contracts documented and audited

This design covers building the Flutter consumer app from scratch. The MVP spec v5.3 defines every screen, interaction, and data field. This document defines the build sequence and file structure.

---

## Architecture Summary

**Two-layer data model:**

- Layer 1 (Local SQLite via drift): Split into `pharmaguide_core.db` (read-only reference tables, overwritten OTA) and `user_data.db` (read-write user tables, available offline, never overwritten). ~180k products, instant offline scan/search.
- Layer 2 (Supabase Remote): Detail blobs fetched on-demand per product view. Auth, stacks, usage tracking, AI proxy.

**On-device scoring:** `score_fit_20` computed by ScoreFitCalculator from local health profile + reference_data. Never stored remotely.

**Animation implementation:** Ship Flutter-native animations first (`AnimationController`, implicit animations, AnimatedSwitcher). Rive assets are explicitly deferred until the core scan/result flow is stable. Any Rive references in older UX notes should be interpreted as motion intent, not an MVP library requirement.

---

## Repo Structure

```
PharmaGuide_ai/
├── lib/
│   ├── main.dart                          # Entry point, ProviderScope, theme
│   ├── app.dart                           # MaterialApp + GoRouter
│   ├── theme/
│   │   └── app_theme.dart                 # ALL colors, text styles, shadows
│   ├── data/
│   │   ├── local/
│   │   │   ├── reference_database.dart    # drift DB (products_core, fts, reference_data)
│   │   │   ├── user_database.dart         # drift DB (user_profile, user_stacks_local, etc.)
│   │   │   ├── database.g.dart            # drift generated
│   │   │   └── db_version_checker.dart    # Supabase manifest version check
│   │   ├── remote/
│   │   │   ├── supabase_service.dart      # Client init + auth helpers
│   │   │   ├── detail_blob_service.dart   # Fetch + cache detail blobs
│   │   │   └── ai_chat_service.dart       # Gemini Edge Function proxy
│   │   └── models/
│   │       ├── product.dart               # Product from products_core
│   │       ├── detail_blob.dart           # Full detail blob parser
│   │       ├── warning.dart               # Sealed Warning class hierarchy
│   │       ├── score_bonus.dart           # Bonus/penalty models
│   │       └── health_profile.dart        # User health profile
│   ├── services/
│   │   ├── score_fit_calculator.dart      # On-device FitScore (E1/E2)
│   │   ├── scan_limit_service.dart        # Freemium enforcement
│   │   └── interaction_checker.dart       # Condition/drug intersection
│   │   └── taxonomy_service.dart          # Validates clinical_risk_taxonomy at startup
│   ├── providers/
│   │   ├── auth_provider.dart             # Supabase auth state
│   │   ├── product_provider.dart          # Product lookup + detail loading
│   │   ├── health_profile_provider.dart   # Local health profile
│   │   ├── stack_provider.dart            # User stack CRUD
│   │   ├── reference_data_provider.dart   # Pre-parsed reference tables
│   │   └── scan_limit_provider.dart       # Usage tracking
│   ├── screens/
│   │   ├── home/
│   │   │   ├── home_screen.dart
│   │   │   ├── hero_card.dart
│   │   │   └── recent_scans_carousel.dart
│   │   ├── scan/
│   │   │   ├── scan_screen.dart           # Camera + barcode detection
│   │   │   ├── result_screen.dart         # Full clinical breakdown
│   │   │   ├── b0_warning_screen.dart     # BLOCKED/UNSAFE gate
│   │   │   └── pillar_cards/
│   │   │       ├── ingredient_quality_card.dart
│   │   │       ├── safety_purity_card.dart
│   │   │       ├── clinical_evidence_card.dart
│   │   │       ├── brand_trust_card.dart
│   │   │       └── personal_match_card.dart
│   │   ├── stack/
│   │   │   ├── stack_screen.dart
│   │   │   └── stack_item_card.dart
│   │   ├── chat/
│   │   │   ├── chat_screen.dart
│   │   │   └── chat_bubble.dart
│   │   └── profile/
│   │       ├── profile_screen.dart
│   │       └── health_chips_sheet.dart
│   └── widgets/
│       ├── floating_tab_bar.dart
│       ├── score_ring.dart                # Animated ring (simple Flutter)
│       ├── score_badge.dart
│       ├── shimmer_card.dart
│       ├── primary_button.dart
│       └── app_bottom_sheet.dart
├── assets/
│   ├── fonts/                             # Inter font files
│   └── db/
│       ├── pharmaguide_core.db            # Bundled from pipeline output
│       └── user_data.db                   # Local user data (created on launch)
├── test/
│   ├── services/
│   │   └── score_fit_calculator_test.dart
│   ├── data/
│   │   └── database_test.dart
│   └── providers/
│       └── product_provider_test.dart
├── pubspec.yaml
├── analysis_options.yaml
└── CLAUDE.md
```

---

## Package Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.0
  supabase_flutter: ^2.5.0
  freezed_annotation: ^2.4.1
  mobile_scanner: ^5.0.0
  hive_flutter: ^1.1.0
  go_router: ^14.0.0
  google_fonts: ^6.2.0
  shimmer: ^3.0.0
  connectivity_plus: ^6.0.0
  json_annotation: ^4.9.0
  path_provider: ^2.1.0
  permission_handler: ^11.3.0
  flutter_local_notifications: ^17.0.0
  flutter_downloader: ^1.11.6
  flutter_hooks: ^0.20.5
  url_launcher: ^6.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0
  drift_dev: ^2.18.0
  riverpod_generator: ^2.4.0
  json_serializable: ^6.8.0
  freezed: ^2.4.1
  flutter_lints: ^4.0.0
```

---

## Phase 1: Foundation (Week 1-2)

**Goal:** App opens, 5 tabs navigate, theme matches spec, SQLite data loads, Supabase connected.

### What gets built:

1. **Project creation:** `flutter create PharmaGuide_ai`, configure pubspec.yaml with all packages
2. **CLAUDE.md:** Project instructions for Claude Code. Must contain:
   - All 10 hard rules from spec Section 12
   - Data contract field corrections (`notes` not `reference_notes`)
   - The full condition_id mapping table (14 conditions) and drug_class_id mapping table (9 drug classes)
   - drift-over-sqflite mandate with reasoning
   - Supabase project URL and anon key
   - Test commands (`flutter test`, `flutter analyze`)
   - The `(SELECT auth.uid())` RLS pattern note for any future Supabase work
3. **app_theme.dart:** Every color, text style, shadow, spacing constant from spec Section 2. Single source of truth.
4. **drift database (database.dart):**
   - Table: `products_core` (61 columns matching pipeline schema exactly)
   - Table: `products_fts` (FTS5 virtual table for search)
   - App-side tables: `product_detail_cache`, `user_profile`, `user_scan_history`, `user_stacks_local`, `user_favorites`
   - Code generation via `build_runner`
5. **Bundle pharmaguide_core.db:** Copy from pipeline output to `assets/db/`. Load at app startup, copy to writable directory.
6. **Reference data parsing:** Load 4 JSON tables from SQLite reference_data at startup. Hold in memory via `referenceDataProvider` singleton. Never re-parse per view.
7. **Taxonomy validation service:** Load `clinical_risk_taxonomy` from `reference_data` at startup and validate that all condition/drug-class UI chips map exactly to pipeline IDs. Fail fast in debug builds if drift is detected.
8. **Supabase client init (supabase_service.dart):**
   - Initialize with project URL + anon key
   - Auth providers: Google, Apple, Email
   - Auto-create anonymous session on first launch (no prompt)
9. **Floating tab bar (floating_tab_bar.dart):** 5 tabs, frosted glass, scan button elevated, labels on all tabs for discoverability and accessibility
10. **GoRouter setup:** 5 tab routes + placeholder screens, plus deep-link validation. Malformed routes should redirect to Home with a generic error state instead of attempting invalid DB lookups.
11. **Reusable widgets:** PrimaryButton, OutlineButton, ScoreBadge, ShimmerCard, AppBottomSheet, ScoreRing (animated count-up, color by score)
12. **ScoreFitCalculator (score_fit_calculator.dart):**
    - Inputs: score_quality_80, breakdown, HealthProfile, reference_data
    - Outputs: FitScoreResult (scoreFit20, scoreCombined100, chips, missingFields)
    - Sub-scores: E1 dosage (0-7), E2a goal (0-2), E2b age (0-3), E2c medical (0-8)
    - Unit tested before any UI work
13. **Hive setup:** guest_scan_count box (freemium), chat_history box
14. **Parser smoke tests:** Add fixture-driven tests that parse a real `products_core` row, one `SAFE` detail blob, one `BLOCKED`/B0 detail blob, one `NOT_SCORED` row, one PDF image URL, and one interaction_summary payload before UI work starts.

### Testable outcome:

App opens on iPhone. 5 tabs navigate. Theme colors match spec. Breakpoint shows product data loaded from SQLite. ScoreFitCalculator passes all unit tests.

---

## Phase 2: Core Scan Loop (Week 2-4)

**Goal:** Scan a barcode, see the full clinical breakdown with real pipeline data.

### What gets built:

1. **Scan screen (scan_screen.dart):**
   - Camera via mobile_scanner
   - Scanner bracket animation (simple Flutter, 3 states: idle/scanning/success)
   - Flash toggle, "Enter Code Manually" text button
   - Permission handling (first launch, granted, denied states)

2. **Scan flow (happy path — spec Section 6.3, steps 11-22):**
   - Barcode detected -> haptic -> bracket success -> pause camera
   - Green banner "Product Identified" (auto-dismiss 1.5s)
   - Check scan limit (guest: Hive, signed-in: increment_usage RPC)
   - Query products_core WHERE upc_sku = ? asynchronously via drift Future to prevent UI block.
   - Handle UPC collision (1:N relationship). Use deterministic ordering: active first, highest score, lowest dsld_id. Show a chooser UI if the top two scores differ by < 5 points.
   - If BLOCKED/UNSAFE -> B0 warning screen
   - If user_profile has data -> run ScoreFitCalculator
   - Slide up result screen

3. **B0 gate (b0_warning_screen.dart):**
   - Red circle with X icon (no score ring, no animation)
   - "CRITICAL WARNING" card with blocking_reason
   - Haptic double-pulse vibration
   - "Report This Product" + "Scan Another Product" buttons

4. **Result screen (result_screen.dart):**
   - Hero: product image (explicitly verify not `.pdf` before CachedNetworkImage), name, brand, score ring, grade, percentile chip. (Even for NOT_SCORED products, display this basic product info).
   - Profile tease banner (if no profile)
   - Verdict banner (SAFE/CAUTION/POOR/UNSAFE/NOT_SCORED colors)
   - Condition alert banner (if interaction_summary intersects user conditions/meds)

5. **5 pillar smart cards (pillar_cards/):**
   - Card 1 — Ingredient Quality (/25): ingredient list, premium form badges, delivery tier, probiotic badge, omega-3 dose adequacy
   - Card 2 — Safety & Purity (/30): cert badges, proprietary blend warning, harmful additives (mechanism + population_warnings), allergens
   - Card 3 — Clinical Evidence (/20): sub-clinical dose warning, interaction warnings (sealed class), dose threshold context, study badges (RCT/SR/MA)
   - Card 4 — Brand Trust (/5): manufacturer violation override, boolean rows, product status
   - Card 5 — Personal Match: locked state (no profile) vs dynamic chips from ScoreFitCalculator

6. **Detail blob loading (detail_blob_service.dart):**
   - Check product_detail_cache first
   - If not cached + online: read `detail_blob_sha256` from `products_core`, derive the hashed detail payload path, then fetch from Supabase Storage
   - Fall back to versioned `detail_index.json` only if `detail_blob_sha256` is absent on an older export
   - Cache in SQLite product_detail_cache
   - Show shimmer on accordion cards while loading
   - If offline: show header only, "Detail unavailable offline" banner

7. **Detail blob model (detail_blob.dart):**
   - @JsonKey annotations for mixed camelCase/snake_case fields
   - Use `freezed` or `json_serializable` with a discriminator/type field (e.g. `@Freezed(unionKey: 'type')`) for safe polymorphic JSON deserialization of the sealed Warning class.
   - Score bonus/penalty models with type-specific fields

8. **"Add to Stack" flow:**
   - Single bottom sheet with animated transitions
   - Timing chips (AM/PM/Custom) -> supply count chips (30/60/90/120)
   - Success checkmark, auto-dismiss

9. **Manual entry + not found:**
   - Text field search sheet -> SQLite lookup
   - If not found in SQLite: show "Product Not Found" sheet -> submit to pending_products
   - No remote product search in v1; Supabase only hosts manifests, blobs, and app-facing user tables

10. **Scan limit enforcement (scan_limit_service.dart):**
    - Guest: Hive guest_scan_count, >= 10 -> upgrade sheet
    - Signed-in: increment_usage RPC, returns `{scans_today, ai_messages_today, limit_exceeded}`
    - Signed-in free limit: If scans_today >= 20 for the current day, show the over-limit sheet
    - Call after barcode resolution but before final result render so `limit_exceeded=true` can block the over-limit experience
    - **Network failure fallback:** If increment_usage RPC fails (network error mid-scan), fall back to client-side Hive count and ALLOW the scan. Never block the user on a network error.

### Testable outcome:

Scan any supplement barcode on your iPhone. See a real score with full clinical breakdown from your pipeline data. Add it to your stack.

---

## Phase 3: Stack & Home (Week 4-5)

**Goal:** Home screen, stack management, search, offline detection. App feels complete.

### What gets built:

1. **Stack tab (stack_screen.dart):**
   - Summary card: gradient, score ring, interaction risk level, product count
   - "My Stack" / "Wishlist" sub-tabs
   - Stack item cards: 72dp height, image, name, dosage/timing, score badge, risk icon
   - Swipe right to delete (red bg, trash icon, snackbar undo)
   - Tap to edit (bottom sheet: dosage, timing, supply count)
   - Empty state: illustration + "Scan a Product" CTA
   - **Write-first to local SQLite** (`user_stacks_local`), then sync to Supabase (`user_stacks`) for signed-in users. Local is the source of truth — Supabase is the sync target. This ensures offline stack editing works. Never build it Supabase-first.
   - Remote stack sync semantics: last-write-wins using `client_updated_at`, with soft deletes represented by `deleted_at` tombstones. Preserve `source_device_id` for diagnostics.

2. **Home tab (home_screen.dart):**
   - Header: greeting + connectivity status (offline = grey cloud icon)
   - Search bar: full-width, 48dp, FTS5 instant results from products_fts
   - Search state must be latest-query-wins. A slower older search result must never overwrite a newer query in the UI.
   - Hero card state A (zero stack): onboarding gradient, "Scan First Product" CTA
   - Hero card state B (active): score ring, product count, interaction risk, "X meds scheduled"
   - Recent scans carousel: horizontal ListView, 140dp cards, score badge, PDF image placeholder
   - Daily AI insight card: placeholder text until Phase 4 (cache 24h)

3. **Offline detection:**
   - connectivity_plus listener
   - Per-tab offline banners
   - SQLite always works offline
   - Scan works offline (products_core is local)
   - Detail blobs + AI chat require internet
   - Signed-in local data remains available offline from `user_data.db`: stack, favorites, scan history, and health profile. Supabase is sync target, not runtime dependency.

4. **DB version update (db_version_checker.dart):**
   - App launch: read local export_manifest
   - If online: check Supabase export_manifest (is_current=true)
   - If newer + min_app_version satisfied: use a background downloader package to fetch the ~90MB+ `.db` file, ensuring the OS doesn't kill it.
   - Verify the downloaded file against remote `checksum` before swap-in
   - Swap in when complete via atomic swap: 1) Close active DB connection. 2) Rename old `pharmaguide_core.db` to `.bak`. 3) Rename new staging DB to `pharmaguide_core.db`. 4) Re-open DB connection. 5) Delete `.bak`. Never block the user. Never overwrite `user_data.db`.
   - If download fails: continue with current DB silently
   - **Must be tested explicitly:** version check must not block main thread, must handle network failure gracefully, must not corrupt the active DB during swap.

### Testable outcome:

Full home screen, stack management, search works instantly, offline mode shows appropriate banners. DB version checker tested against all 4 scenarios.

---

## Phase 4: AI Chat & Profile (Week 5-6)

**Goal:** Full feature set — AI pharmacist and personalized health profile.

### What gets built:

1. **Supabase Edge Function (deploy separately):**
   - TypeScript Edge Function wrapping Gemini 2.5 Flash-Lite
   - Receives: `{ messages: [...], system_prompt: string }`
   - API key server-side only (never in app binary)
   - Implement strict rate limiting, input validation, and request timeout handling to prevent abuse and control token costs.
   - NOTE: Verify Gemini free tier limits before launch (~1000 RPD / 15 RPM as of March 2026)

2. **AI chat screen (chat_screen.dart):**
   - Proactive empty state: sparkle icon, "How can I help you today?"
   - 3 prompt buttons (no stack: static prompts; has stack: dynamic stack-aware)
   - Chat bubbles: user (right, brand color), AI (left, grey), typing indicator (3-dot)
   - Input: rounded field, send icon (active when text present)
   - Quick prompt chips: horizontal scroll above keyboard
   - Disclaimer: "Educational info only -- not medical advice" always visible
   - Offline state: "AI chat requires internet", previous chat viewable from Hive

3. **System prompt builder:**

   ```dart
   String buildSystemPrompt(HealthProfile? profile, List<StackItem> stack)
   ```

   Reads user_profile + user_stacks, includes goals, conditions, allergies, current stack names

4. **AI message limit:**
   - 5/day via increment_usage RPC (p_type = 'ai_message')
   - When limit hit: replace input with banner "You've used your 5 free messages today" + "Explore Pro" CTA
   - Previous messages remain readable

5. **Profile tab (profile_screen.dart):**
   - Privacy header: shield icon, "Privacy-First Design", encrypted on device
   - Auth state: guest -> "Sign in" CTA, signed-in -> avatar/email + "Sign Out"
   - Health context sections (each opens chip-selection bottom sheet):
     - Condition chips: 14 conditions with EXACT condition_id mapping from pipeline taxonomy
     - Medication chips: 9 drug classes with EXACT drug_class_id mapping
     - Health goal chips: from user_goals_to_clusters reference data
   - Settings: notifications toggle, theme (light/dark/system), help, privacy policy, app version
   - State Management: Use `flutter_hooks` (e.g., `useTextEditingController`) or `Form` with `GlobalKey` alongside Riverpod for local form state validation. Do not let profile/stack forms invent their own patterns screen by screen.
   - All health data stored in LOCAL SQLite user_profile only. Never synced to Supabase in MVP.

### Testable outcome:

Chat with AI pharmacist about your supplements. Set up health profile with conditions and medications. See personalized condition alerts on product scans.

---

## Phase 5: Polish & Edge Cases (Week 6-7)

**Goal:** Production-ready for TestFlight submission.

### What gets built:

1. **Error states (spec Section 11):**
   - Slow detail load (>3s): shimmer on cards, hero from SQLite
   - Fetch timeout (>8s): dismiss shimmer, toast "Unable to fetch product details"
   - Damaged barcode: camera continues, no feedback until clean read
   - Not in SQLite: show "Product Not Found" sheet and offer submission to `pending_products`. No remote product search in v1.
   - Supabase fetch fails: toast, show header from SQLite
   - NOT_SCORED: "Not Scored" badge, no ring animation, hide accordion cards with "Insufficient data" but still display basic product hero info.
   - PDF image_url: Explicitly check string extension _before_ passing to `CachedNetworkImage` to avoid internal crash. Show placeholder illustration.
   - UPC collision: deterministic ordering, chooser if ambiguous
   - Auth errors: toast for sign-in failure, silent token refresh, email exists handling
   - General rule: NEVER show raw error codes. Minor = toast. Actionable = bottom sheet.

2. **Shimmer skeletons:** All loading states (detail cards, carousel, stack list)

3. **Haptic feedback audit:**
   - Successful scan: HapticFeedback.heavyImpact()
   - B0 critical warning: HapticFeedback.vibrate() double pulse
   - Primary button tap: HapticFeedback.lightImpact()

4. **Performance audit:**
   - No jank on tab switch, sheet open, score animation
   - Reference data parsed once at startup (verify no re-parse)
   - SQLite queries use indexes (verify EXPLAIN plans)

5. **Dark mode:**
   - ThemeMode.system support in app_theme.dart
   - All colors have dark variants
   - Test on iPhone with dark mode enabled

6. **TestFlight submission:**
   - Xcode: set bundle ID, version, team
   - Archive and upload to App Store Connect
   - Internal testing group

### Testable outcome:

No crashes, no raw errors, smooth animations, dark mode works. Ready for TestFlight beta testers.

---

## Hard Rules (From Spec Section 12)

These are non-negotiable and must be enforced in every phase:

1. `app_theme.dart` is the ONLY place colors, text styles, and shadows are defined
2. Server-side scan limits are non-negotiable (Supabase RLS enforces for signed-in users)
3. No Edge Function for scoring. ScoreFitCalculator is Dart, local, instant
4. Gemini proxy Edge Function IS required. API key never in app binary
5. `score_quality_80` can be NULL. Every display path must null-guard. Never show 0
6. Condition AND drug_class chip values MUST match pipeline taxonomy IDs exactly
7. Parse reference_data JSON ONCE at startup. Never re-parse on every product view
8. NOT_SCORED verdict: show "Not Scored". Never a score ring
9. image_url may be a PDF link. Always check before rendering as image
10. Health profile (user_profile SQLite) never syncs to Supabase in MVP

---

## Supabase Connectivity Requirements

Before Phase 2 scan testing can begin:

- Supabase project live with v2.0.0 schema applied
- At least one export synced (staging/live count may vary; the app architecture targets the full `products_core` export scale)
- Flutter app can read export_manifest via anon key
- Flutter app can download a detail blob from Storage

These are already satisfied — Supabase is live with data.

**Storage URL patterns for Flutter:**

- DB file: `https://omayamxacvacrnvdvzhr.supabase.co/storage/v1/object/public/pharmaguide/v{version}/pharmaguide_core.db`
- Detail index (fallback / audit): `https://omayamxacvacrnvdvzhr.supabase.co/storage/v1/object/public/pharmaguide/v{version}/detail_index.json`
- Detail blob payload: `https://omayamxacvacrnvdvzhr.supabase.co/storage/v1/object/public/pharmaguide/shared/details/sha256/{blob_sha256[0:2]}/{blob_sha256}.json`
- Get `version` and `checksum` from: `export_manifest` table WHERE `is_current = true`

---

## Data Contracts

The Flutter app consumes data defined in these pipeline repo docs:

- `scripts/FINAL_EXPORT_SCHEMA_V1.md` — SQLite schema + detail blob structure
- `scripts/FLUTTER_DATA_CONTRACT_V1.md` — Screen-by-screen data mapping
- `scripts/sql/supabase_schema.sql` — Supabase tables, RPCs, RLS
- `scripts/PharmaGuide Flutter MVP Dev.md` — Complete UI/UX specification (v5.3)

The pipeline export field `notes` (not `reference_notes`) is the correct field name for ingredient/additive detail text. Use `notes` to match the actual export.
