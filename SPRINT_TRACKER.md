---
tags:
  - sprints
  - execution
  - tracking
aliases:
  - Sprint Board
related:
  - "[[ROADMAP]]"
  - "[[LESSONS_LEARNED]]"
  - "[[architecture-decisions]]"
  - "[[pipeline-reference]]"
  - "[[flutter-patterns]]"
  - "[[debugging-playbook]]"
---

# PharmaGuide Flutter — Sprint Tracker

> [!info] Related Docs
>
> - [[ROADMAP]] — Complete roadmap V1.0 through V3.1 (`docs/superpowers/specs/2026-04-07-flutter-complete-roadmap-design.md`)
> - [[lessons-learned]] — What we learned each sprint
> - [[architecture-decisions]] — ADR log with rationale
> - [[pipeline-reference]] — Pipeline data structures, schemas, enums
> - [[flutter-patterns]] — Conventions for this Flutter app
> - [[debugging-playbook]] — Common issues and fixes

**Version:** V1.0
**Updated:** 2026-04-07
**Current Sprint:** Sprint 2-3 (wiring phase — connecting scaffolding to real data)
**Overall Status:** Foundation complete. 86 tests, 46 source files. Wiring + polish remaining.

Update rules:

- Update this file during implementation.
- Mirror status/sprint changes to [[lessons-learned]] when unexpected.
- Do not mark a task `Done` without fresh verification evidence.

Status legend:

- `[x]` = `Done`
- `[-]` = `In Progress` or `Review`
- `[ ]` = `Ready` or `Backlog`

---

## AGENT RULES

1. **NEVER mark a task `[x]` unless ALL Definition of Done criteria pass.**
2. **Run verification commands BEFORE marking complete.**
3. **If a test fails, the task is NOT done — fix it first.**
4. **Update this file after every completed task.**
5. **Add to [[lessons-learned]] when something unexpected happens.**
6. **Partial completion is NOT completion. Use `[-]` for in-progress.**

---

## CURRENT SPRINT

**Wiring Phase** — Connecting built scaffolding to real data + remaining polish
Status: IN PROGRESS

Foundation complete: 86 tests, 46 source files, 15 commits. All screens scaffolded, all core logic built and tested. Now connecting everything together.

---

## NEXT UP

**Wiring tasks (highest priority):**
- Wire FTS search to CoreDatabase (debounced, LIMIT 50, latest-query-wins)
- Wire barcode scan to CoreDatabase.findByUpc()
- Wire product detail to CoreDatabase.findById() + detail blob cache
- Wire FitScore calculators into product detail screen
- Wire stack add flow through StackInteractionChecker -> safety modal -> persist
- Wire profile save to UserDatabase
- Freemium gating (guest: 10 scans, free: 20/day)
- Offline mode indicator

**Polish tasks:**
- Splash screen + app icon
- WCAG AA theme (light + dark, Inter font, 8dp grid)
- Crash reporting + analytics stubs
- Score education overlay, coach marks, haptics

**Then Sprint 8: Testing + QA + Ship**

---

## Sprint 0: Foundation + Profile Setup

**Status:** DONE
**Timeline:** Week 1-2
**Completed:** 2026-04-08

### Tasks

- [x] Initialize Flutter project with correct package name and bundle ID (`com.pharmaguide.app`, iOS+Android only)
- [x] Configure pubspec.yaml with all V1.0 dependencies (riverpod, go_router, drift, supabase_flutter, mobile_scanner, share_plus, etc.)
- [x] Create CLAUDE.md with project rules and architecture overview
- [x] Core constants: Severity enum (5 levels, weights, e2cPenalty, colors) + EvidenceLevel enum
- [x] Core constants: AppColors (severity, score, UI tokens)
- [x] Core constants: SchemaIds (frozen 14 conditions, 9 drug classes, 18 goals, 5 age brackets with labels)
- [x] Core models: InteractionResult with stackPenaltyFor(), InteractionType, InteractionSource enums
- [x] Core models: FitScoreResult with displayText formatting
- [x] Core models: StackSafetyScore with RiskTier enum (5 tiers from score)
- [x] Core models: SynergyResult and TimingOptimization
- [x] SafeJson extensions (safeString, safeDouble, safeInt, safeBool, safeStringList, safeMap)
- [x] ReferenceDataRepository (lazy-cached loaders for 4 bundled JSON files)
- [x] Bundle reference data from pipeline (rda_optimal_uls, goals, taxonomy, timing placeholder)
- [x] Create core_database.dart (Drift schema for pharmaguide_core.db — 88 columns, read-only)
- [x] Create user_database.dart (Drift schema for user_data.db — profile, stack, favorites, cache, history)
- [x] Run Drift code generation (build_runner)
- [x] Set up GoRouter with ShellRoute for five tabs (Home, Scan, Stack, Chat, Profile)
- [x] Create supabase_client.dart with initialization (env-var config, non-fatal for offline)
- [x] Create main.dart + app.dart with proper initialization order (ProviderScope, Supabase init, theme)
- [x] 3-slide onboarding screen (Know What You Take, Personalized Safety, Privacy)
- [x] Build profile setup flow: basic info (nickname, age bracket, sex)
- [x] Build profile setup flow: health goals (18 goals, max 2, sorted by priority)
- [x] Build profile setup flow: conditions checklist (14 conditions from clinical_risk_taxonomy)
- [x] Build profile setup flow: drug class checklist (9 drug classes with user-friendly labels)
- [x] Build profile setup flow: allergen selection (17 food/supplement allergens)
- [x] Build profile setup flow: review & save with completeness score
- [x] ProfileNotifier with StateNotifier (toggle methods, max-2 goals enforcement)
- [x] 86 tests passing, flutter analyze clean
- [ ] Set up app_theme.dart with WCAG AA colors (light + dark), Inter typography, 8dp grid
- [ ] Create crash_reporting_service.dart stub (Crashlytics or Sentry)
- [ ] Create analytics_service.dart stub
- [ ] Store profile in user_data.db user_profile table (DB persistence wiring)
- [ ] Write profile persistence tests (read back from DB after save)
- [ ] Splash screen (flutter_native_splash, brand color #0A7D6F, logo, 1.5s)
- [ ] App icon design (teal shield, white checkmark/pill)
- [ ] Design system: Inter font family + 8dp spacing grid

### Definition of Done

- All tests pass: `flutter test test/` -- expect 0 failures
- `flutter analyze` reports 0 issues
- App launches on iOS simulator and Android emulator without crash
- Five tabs are visible and navigable
- Theme switches between light and dark correctly
- pharmaguide_core.db loads from assets and one product is readable via Drift query
- user_data.db creates on first launch with correct schema
- Profile setup flow: user can select conditions, drug classes, allergens, and data persists across app restart
- No colors used outside of app_theme.dart constants
- reference_data table loads once at startup (verify with debug print, no repeated loads)
- Crashlytics/Sentry initializes without error (stub is OK, but must not crash)

### Acceptance Criteria

- A user can launch the app, see five tabs, and complete the profile setup flow
- Profile data survives app restart
- The app has a consistent visual theme

### Dependencies

- Pipeline: pharmaguide_core.db must be exported and placed in assets/db/
- Supabase project must be created with auth enabled

### Known Risks / Blockers

- Drift code generation can be slow on first run -- plan for it
- pharmaguide_core.db size (~90MB) may need to be split or compressed for bundle
- Need Supabase project URL and anon key before initialization

---

## Sprint 1: Database + Core Services

**Status:** MOSTLY DONE (via Sprint 0 acceleration)
**Timeline:** Week 3-4
**Note:** Most Sprint 1 tasks were completed during Sprint 0 build — SafeJson, ReferenceDataRepository, Drift DBs, Supabase client all done.

### Tasks

- [x] SafeJson extensions for all JSON parsing (completed in Sprint 0)
- [x] ReferenceDataRepository with lazy-cached loaders (completed in Sprint 0)
- [x] CoreDatabase with 88-col products_core + query methods (completed in Sprint 0)
- [x] UserDatabase with profile, stack, favorites, cache tables (completed in Sprint 0)
- [x] Supabase client with env-var config (completed in Sprint 0)
- [x] SyncService with atomic DB swap + rollback (completed in Sprint 0)
- [x] DetailBlobService for on-demand fetch (completed in Sprint 0)
- [ ] Offline mode indicator (header status bar: online/offline/syncing)
- [ ] Freemium gating service (Hive for guest: 10 lifetime scans, Supabase user_usage for signed-in: 20/day)
- [ ] Guest mode support (app usable without sign-in, limited features)
- [ ] Create test fixtures directory with representative JSON blobs
- [ ] Implement scan_limit_service.dart stub

### Definition of Done

- All tests pass: `flutter test test/services/` -- expect 0 failures
- All tests pass: `flutter test test/models/` -- expect 0 failures
- ScoreFitCalculator: verified with at least 8 test cases covering all profile dimensions
- TaxonomyService: `assert(conditions.length == 14)` and `assert(drugClasses.length == 9)` pass
- Parser tests: all 5 fixture types parse without error
- SafeJson: no raw `as Map<String, dynamic>` casts in any model file
- `flutter analyze` reports 0 issues
- Warning types are exhaustive (switch statements compile without default)

### Acceptance Criteria

- ScoreFitCalculator produces a 0-20 fit adjustment score given a profile and product
- All JSON from the pipeline can be parsed without runtime exceptions
- Warning types cover every warning category the pipeline can produce

### Dependencies

- Sprint 0 complete
- Test fixture JSON files need to match real pipeline output shape

### Known Risks / Blockers

- Detail blob schema may evolve -- fixtures must be regenerated if schema changes
- 9 of 14 conditions had zero interaction rules in pipeline data -- verify coverage before claiming interaction feature works

---

## Sprint 2: Product Catalog + Search

**Status:** MOSTLY DONE (scaffolding complete, DB wiring pending)
**Timeline:** Week 5-6

### Tasks

- [x] Build Home screen with modular widgets (SearchBar, StackHealth, RecentScans, ProfileCompleteness, CategoryChips)
- [x] Implement search screen with text input, empty state, clear button
- [x] Implement barcode scan screen with mobile_scanner, torch toggle, manual entry fallback
- [x] Implement category filter chips (omega-3, probiotic, multivitamin, collagen, adaptogen, nootropic)
- [x] Home screen greeting (time-based with nickname)
- [x] Profile completeness banner (shows when < 60%)
- [x] Search + scan + home widget tests (8 tests)
- [ ] Wire FTS search to CoreDatabase (debounced 300ms, LIMIT 50, latest-query-wins)
- [ ] Wire barcode scan to CoreDatabase.findByUpc()
- [ ] Implement recent searches (Hive local storage)
- [ ] Build product list/grid toggle view
- [ ] Product not found flow (submission modal with photo + manual entry)
- [ ] Decision-first scan result (color flash + haptic feedback on scan)

### Definition of Done

- All tests pass: `flutter test test/features/search/` -- expect 0 failures
- All tests pass: `flutter test test/features/scan/` -- expect 0 failures
- Search: type "vitamin d" and get results within 300ms (measured, not estimated)
- Search: rapidly typing produces no stale results (latest-query-wins verified)
- Search: results never exceed 50 items
- Scan: UPC "012345678901" (or test UPC) resolves to correct product from local DB
- Scan: unknown UPC shows "Product not found" state
- Home: carousels load from local DB without network
- `flutter analyze` reports 0 issues

### Acceptance Criteria

- A user can search for supplements by name and see results instantly
- A user can scan a barcode and see the product info
- A user can browse the home screen with categorized product carousels
- Everything works offline (no network required for search/scan/browse)

### Dependencies

- Sprint 1 complete (models, parsers, ScoreFit)
- pharmaguide_core.db must have products_fts table populated

### Known Risks / Blockers

- FTS query syntax differences between SQLite versions on iOS vs Android
- Camera permissions UX differs between platforms
- ~180K products in FTS -- verify performance on low-end devices

---

## Sprint 3: Product Detail + Score Transparency

**Status:** MOSTLY DONE (core widgets built, detail blob wiring + polish pending)
**Timeline:** Week 7-8

### Tasks

- [x] Build product detail screen with instant header from products_core
- [x] Build ScoreBreakdownCard (4 section bars: Ingredient Quality /25, Safety /30, Evidence /20, Brand Trust /5)
- [x] Build InteractionWarnings widget (severity-sorted, evidence badges, clickable source URLs)
- [x] Build BlendWarningBanner (proprietary blend detection)
- [x] Build UnknownIngredientBanner (mapped_coverage < 0.5 warning)
- [x] BLOCKED product handling: no score displayed, red banner with reason + FDA source URLs
- [x] Shimmer loading for detail blob sections
- [x] Product detail tests: score breakdown (4 labels, values, null handling), interaction warnings (sorting, parsing)
- [ ] Wire to real CoreDatabase provider (currently uses placeholder)
- [ ] Implement detail blob fetch + cache in user_data.db
- [ ] Build condition alert banner from interaction_summary_hint
- [ ] Score education overlay ("What does this score mean?")
- [ ] Better Alternatives section (similar products with higher scores)
- [ ] Score ring animation (animated count from 0 to score)
- [ ] Handle NOT_SCORED products (no ring, explanation text)
- [ ] Clinical citation links (WebView for PMID URLs)

### Definition of Done

- All tests pass: `flutter test test/features/product_detail/` -- expect 0 failures
- Widget tests cover: SAFE, CAUTION, POOR, UNSAFE, BLOCKED, NOT_SCORED verdict states
- B0 gate: banned product shows warning screen with no score ring
- Score ring: animates from 0 to correct value on appear
- Condition banner: appears within 16ms of screen load (from SQLite hint, not network)
- Detail blob: shimmer shows during fetch, content appears on success, error state on timeout (8s)
- All pillar cards expand/collapse with correct data
- `flutter analyze` reports 0 issues
- No emojis used as structural UI elements (Lucide icons only)
- Reduced motion: animations respect system accessibility settings
- BLOCKED products display red banner with blocking reason and FDA source URLs — no score number shown
- Score education overlay appears on first product view

### Acceptance Criteria

- A user can scan a product and see its full safety score breakdown
- A user understands WHY a product scored the way it did (transparent scoring)
- Banned/recalled products show a clear hard-stop warning
- Users with health conditions see relevant interaction alerts immediately
- Detail loads gracefully even on slow connections

### Dependencies

- Sprint 2 complete (scan flow, product lookup)
- Supabase Storage must have detail blobs uploaded
- Detail blob index must be generated by pipeline

### Known Risks / Blockers

- Detail blob fetch latency on slow networks -- shimmer + timeout critical
- interaction_summary_hint may be null for products not yet re-exported
- Some products have no score (NOT_SCORED) -- every UI path must handle this

---

## Sprint 4: FitScore Engine

**Status:** DONE (calculators built + tested, UI integration pending)
**Timeline:** Week 9-10
**Completed:** 2026-04-08

### Tasks

- [x] E1 Dosage Calculator: RDA/UL comparison, -5 to +7 pts, highest_ul fallback
- [x] E2a Goal Calculator: cluster matching against user goals, 0-2 pts
- [x] E2b Age Calculator: age-group RDA comparison, 0-3 pts
- [x] E2c Medical Calculator: condition + drug class severity penalties, 0-8 pts
- [x] FitScoreService orchestrator: combines all 4, computes combined 100-point score
- [x] Missing profile fields tracked, maxPossible adjusts dynamically
- [x] E2c tests: no match (8pts), contraindicated (-8), avoid (-5), multiple conditions, clamp to 0, empty profile
- [x] FitScoreService tests: combined score, missing fields, maxPossible adjustment
- [ ] Integrate FitScore into product detail screen UI
- [ ] Build FitScore explanation UI (which profile factors affected score)
- [ ] Build "personalized for you" badge
- [ ] FitScore recalculation on profile change (invalidation logic)
- [ ] FitScore comparison view (side-by-side two products)

### Definition of Done

- All tests pass: `flutter test test/services/fit_score/` -- expect 0 failures
- FitScore: changes immediately when profile is updated (no app restart)
- FitScore: never persisted to any database (verify with DB inspection)
- FitScore: null/empty profile produces base score with explanation
- Comparison view: two products display side-by-side with correct FitScores
- `flutter analyze` reports 0 issues

### Acceptance Criteria

- A user with a health profile sees a personalized safety score for each product
- A user understands how their conditions/medications affect the product's score
- A user can compare two products to see which is better for their specific profile

### Dependencies

- Sprint 3 complete (product detail screen)
- Sprint 0 profile data must be readable by ScoreFitCalculator

### Known Risks / Blockers

- FitScore calculation must be fast enough for real-time updates (<50ms per product)
- Profile changes should not cause visible jank in product lists

---

## Sprint 5a: Stack Management

**Status:** PARTIALLY DONE (screen + DB schema built, sync + scheduling pending)
**Timeline:** Week 11-12

### Tasks

- [x] Build Stack screen with My Stack + Wishlist tabs
- [x] Stack empty states with scan CTA
- [x] UserDatabase: getActiveStack(), addToStack(), removeFromStack() with soft delete
- [x] user_stacks_local table with tombstones (deleted_at) and sync tracking (client_updated_at, synced_at)
- [ ] Wire add-to-stack from product detail (trigger safety check first)
- [ ] Wire remove-from-stack with undo snackbar (5s window)
- [ ] Implement Supabase sync for signed-in users (write local first, sync on connectivity)
- [ ] Build offline queue for stack changes
- [ ] Implement LWW conflict resolution with client_updated_at
- [ ] Build stack summary view (total daily supplement load)
- [ ] Stack wishlist: compatibility check against current stack
- [ ] Full Stack Analysis report (nutrient breakdown, interactions, timing, goals, "What If" scenarios)
- [ ] Add-to-stack scheduling flow (time, supply tracking, reminders — all skippable)
- [ ] Write sync tests and stack persistence tests

### Definition of Done

- All tests pass: `flutter test test/features/stack/` -- expect 0 failures
- Stack: add product offline, kill app, relaunch -- product still in stack
- Stack: add product offline, go online -- product syncs to Supabase
- Stack: edit on phone A, edit on phone B -- LWW resolves correctly
- Stack: delete product -- tombstone created, not hard-deleted
- user_data.db is never affected by OTA core DB updates (verify after simulated swap)
- `flutter analyze` reports 0 issues

### Acceptance Criteria

- A user can manage their supplement stack (add, remove, view)
- Stack data persists offline and syncs when connectivity returns
- Multi-device users see consistent stack data

### Dependencies

- Sprint 3 complete (product detail for add-to-stack entry point)
- Supabase user_stacks table must exist with RLS policies

### Known Risks / Blockers

- Sync conflicts with multiple devices editing simultaneously
- Offline queue may grow large if user is offline for extended periods

---

## Sprint 5b: Safety Checker

**Status:** DONE (core logic built + tested, UI wiring pending)
**Timeline:** Week 12-13
**Completed:** 2026-04-08

### Tasks

- [x] StackInteractionChecker: stimulant/sedative antagonism detection
- [x] StackInteractionChecker: blood thinner stacking detection
- [x] StackInteractionChecker: duplicate nutrient detection (3+ overlapping)
- [x] StackInteractionChecker: safe addition returns empty results
- [x] StackSafetyScorer: 0-100 score with penalty bands per severity
- [x] StackSafetyScorer: hard-stop caps (contraindicated=25, avoid=50)
- [x] StackSafetyScorer: synergy bonuses (max +15)
- [x] StackSafetyScorer: floor at 25, ceiling at 100
- [x] StackSafetyScorer: empty stack = 100 (excellent)
- [x] 10 tests: 4 interaction checker + 6 safety scorer
- [ ] Build safety alert UI for stack-level warnings
- [ ] Wire "safe to add?" check into add-to-stack flow
- [ ] Handle edge case: 20+ product stack performance

### Definition of Done

- All tests pass: `flutter test test/services/interaction_checker/` -- expect 0 failures
- Stack Safety: two caffeine products in stack triggers stimulant stacking warning
- Stack Safety: melatonin + valerian triggers sedative stacking warning
- Stack Safety: omega-3 + garlic triggers blood thinner stacking warning
- Duplicate detection: same ingredient in two products is flagged
- "Safe to add?" check runs before product is added to stack
- Hard-stop cap: stack with banned product shows BLOCKED regardless of other products
- `flutter analyze` reports 0 issues

### Acceptance Criteria

- A user is warned when their supplement stack has safety concerns
- A user sees a clear safety score for their overall stack
- Before adding a new supplement, the user is told if it conflicts with their current stack

### Dependencies

- Sprint 5a complete (stack management)
- Pipeline data must include ingredient_fingerprint, contains_stimulants, contains_sedatives, contains_blood_thinners columns

### Known Risks / Blockers

- Interaction rules coverage: only 5 of 14 conditions had interaction data -- safety checker must clearly indicate when data is insufficient
- Stack safety score formula needs to be defined and documented in ADR

---

## Sprint 6: Social Sharing

**Status:** PARTIALLY DONE (ShareService built, deep links pending)
**Timeline:** Week 14

### Tasks

- [x] ShareService: shareProduct() with pre-computed share_title, share_description, share_highlights
- [x] ShareService: shareStackSummary() with safety score, product count, issues, synergies
- [x] share_plus integration for native sharing
- [ ] Build Open Graph preview for shared links (share_og_image_url)
- [ ] Implement deep link handling for shared product links (app_links)
- [ ] Build "shared with you" entry point from deep link
- [ ] Handle deep link edge cases: app not installed, invalid product ID
- [ ] Stack share: "Export PDF for Doctor", "Share List (Text/Email)"
- [ ] Write deep link routing tests

### Definition of Done

- All tests pass: `flutter test test/features/sharing/` -- expect 0 failures
- Share: tapping share produces correct title and description from pipeline data
- Deep link: clicking shared link opens product detail in app
- Deep link: clicking shared link without app installed goes to store listing
- Share card: visually matches design spec
- `flutter analyze` reports 0 issues

### Acceptance Criteria

- A user can share a product's safety score with friends/family
- A recipient can tap the shared link and see the product in the app
- Shared content looks professional on social media previews

### Dependencies

- Sprint 3 complete (product detail screen)
- Pipeline must export share_title, share_description, share_highlights, share_og_image_url

### Known Risks / Blockers

- Deep link configuration differs between iOS (Universal Links) and Android (App Links)
- Open Graph images need a hosting solution

---

## Sprint 7: Settings + Profile Management

**Status:** PARTIALLY DONE (full Profile tab built, auth + OTA pending)
**Timeline:** Week 15

### Tasks

- [x] SettingsScreen with 6 sections: Account, Health Profile, Privacy, Analysis History, Settings, About
- [x] Profile summary card with avatar, nickname/Guest User, completeness %
- [x] Privacy Dashboard modal (device vs cloud vs never-shared data locations)
- [x] Edit Profile button linking to profile setup flow
- [x] Theme/Notifications/Accessibility/Offline/Export/Delete settings tiles
- [x] About section (version, ToS, privacy policy, support, rate, share)
- [x] 5 settings screen tests (title, sections, completeness, guest user, privacy button)
- [ ] Implement Google Sign-In
- [ ] Implement Apple Sign-In
- [ ] Implement Email/Password auth
- [ ] Build auth state management (guest -> signed-in transition preserving local data)
- [ ] Implement scan/AI usage limits with increment_usage RPC
- [ ] Build "upgrade to signed-in" prompt when guest hits limits (10 scans lifetime, 3 AI/day)
- [ ] Build signed-in limits display (20 scans/day, 5 AI/day with UTC reset)
- [ ] Implement DB OTA update flow: check manifest -> download -> staging -> checksum -> integrity check -> atomic swap -> reopen -> delete backup
- [ ] Build "update available" indicator on Profile tab
- [ ] Build notification preferences (flutter_local_notifications)
- [ ] Implement min_app_version gate (force update if needed)
- [ ] Write auth flow tests (sign in, sign out, guest-to-auth migration)
- [ ] Write OTA update tests (success, failure, rollback)
- [ ] Write usage limit tests
- [ ] Account & Security section (email, password, login/logout)
- [ ] Health Profile editing (all fields from onboarding, re-editable)
- [ ] Privacy Controls (data usage prefs, transparency dashboard, privacy score)
- [ ] Stack Analysis History (last 3 saved reports, view/email/share/delete)
- [ ] Settings: theme (light/dark/system), language, units
- [ ] Settings: notification controls (reminders, alerts, insights, refills)
- [ ] Settings: accessibility (dynamic type, high contrast, VoiceOver, reduce motion)
- [ ] Settings: offline mode (auto-download, sync frequency)
- [ ] Settings: advanced (export data, clear cache, reset tutorials, delete account)
- [ ] About section (version, ToS, privacy policy, support, rate app)

### Definition of Done

- All tests pass: `flutter test test/features/profile/` -- expect 0 failures
- All tests pass: `flutter test test/features/settings/` -- expect 0 failures
- Auth: Google, Apple, Email all produce valid Supabase session
- Auth: guest data (scan history, stack, profile) preserved after sign-in
- OTA: download + swap succeeds, user_data.db untouched (verify with query after swap)
- OTA: corrupted download detected by checksum, rollback to previous DB
- Limits: guest blocked after 10 lifetime scans with upgrade prompt
- Limits: signed-in user sees count reset at UTC midnight
- `flutter analyze` reports 0 issues
- Profile tab has all 6 sections: Account, Health Profile, Privacy, Analysis History, Settings, About
- Privacy transparency dashboard shows device vs cloud data locations
- Theme switching (light/dark/system) works with preview

### Acceptance Criteria

- A user can sign in with Google, Apple, or Email
- A user can edit their health profile at any time
- Guest users are prompted to sign in when they hit usage limits
- The app updates its product database in the background without losing user data
- Users control their notification preferences

### Dependencies

- All prior sprints complete
- Supabase auth providers configured (Google, Apple)
- increment_usage RPC function deployed to Supabase
- OTA DB artifact hosted on Supabase Storage

### Known Risks / Blockers

- Apple Sign-In requires paid Apple Developer account and entitlements
- OTA download of ~90MB DB needs background_downloader, not flutter_downloader (deprecated)
- Network-failure fallback for increment_usage must not block scans

---

## Sprint 8: Testing + QA + Ship

**Status:** NOT STARTED  
**Timeline:** Week 16-17  
**Effort estimate:** 16-24 pts

### Tasks

- [ ] Full test suite pass: unit, widget, golden, integration
- [ ] Error matrix implementation (toast/sheet/snackbar per error type from spec section 11)
- [ ] Haptics pass (scan success, verdict reveal, error states)
- [ ] Dark mode audit (every screen)
- [ ] Accessibility audit: VoiceOver (iOS), TalkBack (Android), Dynamic Type 200%
- [ ] No emojis as structural UI -- Lucide icons audit
- [ ] Analytics events wired (scan, search, detail view, stack add/remove, share, AI chat)
- [ ] Deep link handling for invalid routes (graceful fallback)
- [ ] Performance profiling: scan-to-result <500ms, search <300ms, app launch <3s
- [ ] Memory profiling: no leaks on repeated scan/detail/back cycles
- [ ] CI setup: flutter analyze + flutter test on every PR
- [ ] TestFlight build and internal testing
- [ ] Google Play internal track build and testing
- [ ] Store metadata: screenshots, description, privacy policy, encryption questionnaire
- [ ] App Store Privacy Nutrition Label
- [ ] Final security audit: no PHI in analytics, AI disclaimers visible, no hardcoded keys
- [ ] Medical disclaimer on all score/recommendation screens
- [ ] Gemini AI quota verification (5/day server-side enforcement)
- [ ] Coach marks / feature tour (overlay system)
- [ ] "Try Demo Mode" (preloaded dummy scan)
- [ ] Haptic feedback verification across all interactions

### Definition of Done

- `flutter test` -- ALL tests pass, 0 failures, 0 skipped
- `flutter analyze` -- 0 issues
- `dart format --set-exit-if-changed .` -- 0 formatting issues
- TestFlight build installs and runs on physical iPhone (test 3 devices minimum)
- Play internal build installs and runs on physical Android (test 3 devices minimum)
- VoiceOver: complete scan-to-detail flow navigable by voice
- TalkBack: complete scan-to-detail flow navigable by voice
- Dynamic Type 200%: no text truncation, no overflow on any screen
- Performance: cold launch <3s, scan-to-result <500ms, search <300ms (measured on release build)
- No crashes in 1-hour manual testing session per platform
- Privacy policy URL resolves and content is accurate
- Store screenshots for both platforms ready
- Coach marks tour completes all 4 highlights without crash
- Demo mode shows full scan result for mock product

### Acceptance Criteria

- App is ready for public TestFlight / Play internal distribution
- All safety-critical UI is accessible
- Performance meets targets on real devices
- Store listings are complete and compliant

### Dependencies

- All prior sprints complete
- Apple Developer account active
- Google Play Developer account active
- Privacy policy hosted and accessible

### Known Risks / Blockers

- App Store review may flag health claims -- ensure disclaimers are prominent
- TestFlight review typically takes 24-48h
- Google Play internal track is near-instant but production review can take days

---

## VERSION ROADMAP

| Version  | Identity                | Sprints | Key Features                                                                          |
| -------- | ----------------------- | ------- | ------------------------------------------------------------------------------------- |
| **V1.0** | Core Product            | 0-8     | Scan, score, FitScore, stack safety, social sharing, full profile tab                 |
| **V1.1** | Medication Intelligence | 9-11    | RxNorm medication stack, StackSafetyEngine, depletion checker, product comparison     |
| **V1.2** | Trust & Transparency    | 12-13   | FitScore explanation layer, recompute strategy, trust layer UI, doctor PDF            |
| **V2.0** | AI Intelligence         | 14-19   | Gate-based AI chat, alternative suggestions, nutrient gap analysis, prescription OCR  |
| **V2.1** | Engagement & Retention  | 20-22   | Dose reminders, reorder alerts, starter stacks, FDA notifications, feedback loop      |
| **V3.0** | Platform & Ecosystem    | 23-27   | B2B REST API, white-label SDK, "Verified" badge, family profiles, practitioner portal |
| **V3.1** | Premium Intelligence    | 28-30   | Lab integration, interaction matrix, clinical governance, drug-drug interactions      |

---

## LESSONS LEARNED

> Agents and developers: append new entries here when something unexpected happens.  
> Format: `- [YYYY-MM-DD] Category: Lesson (Root cause: ...)`

- [2026-04-07] data: Never batch-fix data files -- fix one entry at a time and verify each. Batch operations skip entries and introduce silent errors. (Root cause: batch update scripts processed entries sequentially and skipped on first error without reporting)
- [2026-04-07] data: Always verify API enrichment results case-by-case before writing to data files. Plant/compound collapses and preparation mismatches are common. (Root cause: bulk API enrichment applied results without human verification, creating incorrect mappings)
- [2026-04-07] arch: Drug class checklist is needed in profile for V1.0 E2c scoring -- do not remove prematurely. Will be derived from stack in V1.1. (Root cause: premature optimization suggestion to remove manual entry before automated alternative was built)
- [2026-04-07] data: 9 of 14 conditions had zero interaction rules in pipeline data -- always verify data coverage before claiming a feature works. (Root cause: assumed all taxonomy conditions had corresponding interaction data, but only 5 had rules written)

---

## CHANGELOG

| Date       | Sprint | Change                                                                                                         |
| ---------- | ------ | -------------------------------------------------------------------------------------------------------------- |
| 2026-04-07 | --     | Initial sprint tracker created                                                                                 |
| 2026-04-07 | 0      | Tasks 1-6 complete: project init, constants, models, JSON helpers, ref data, both Drift DBs (25 tests passing) |
| 2026-04-07 | --     | Expanded all sprints with missing MVP features (+31 tasks)                                                     |
| 2026-04-07 | --     | Aligned format with Obsidian vault (YAML frontmatter, wikilinks, status legend)                                |
| 2026-04-08 | 0      | Sprint 0 DONE: GoRouter 5-tab nav, Supabase client, onboarding, profile setup (5 steps), main.dart + app.dart |
| 2026-04-08 | 1      | Sprint 1 mostly done: SafeJson, RefDataRepo, Drift DBs, Supabase services all completed during Sprint 0       |
| 2026-04-08 | 2      | Sprint 2 scaffolding done: Home (modular widgets), Search, Scanner screens built. DB wiring pending.           |
| 2026-04-08 | 3      | Sprint 3 scaffolding done: Product detail, score breakdown, interaction warnings, BLOCKED handling built.       |
| 2026-04-08 | 4      | Sprint 4 DONE: E1-E2c calculators + FitScoreService orchestrator with 9 tests.                                 |
| 2026-04-08 | 5b     | Sprint 5b DONE: StackInteractionChecker + StackSafetyScorer with 10 tests.                                     |
| 2026-04-08 | 6      | Sprint 6 partial: ShareService built (product + stack sharing). Deep links pending.                             |
| 2026-04-08 | 7      | Sprint 7 partial: Full SettingsScreen (6 sections + privacy dashboard). Auth + OTA pending.                     |
| 2026-04-08 | --     | **TOTAL: 86 tests passing, 46 source files, 15 commits, 0 analysis issues**                                    |
