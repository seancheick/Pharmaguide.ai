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
**Updated:** 2026-04-11
**Current Sprint:** Sprint 9 (Catalog v3.4.x DONE) → Sprint 10 (Stack Nutrient Safety M1 DONE) → Sprint 11 (Interaction DB pipeline) → Sprint 8 (ship gate)
**Overall Status:** Sprints 0-3, 9, 10 fully done. **204 Flutter tests + 3,259 pipeline tests** all green. M1 stack nutrient accumulation panel shipped. Interaction DB spec v2.1 written. Target: complete Sprints 4-15 by 2026-05-11 (4 weeks) for V1.0 ship.

## TARGET: Complete Sprints 4–15 by 2026-05-11

| Week | Focus | Sprints |
|---|---|---|
| Wk 1 | Wrap M1 polish + display widgets + FitScore UI | 4 (FitScore UI), 13 (Display widgets), 17 (e1 bug fix) |
| Wk 2 | Interaction DB pipeline + Flutter binding | 11 (M2), 12 (M3) |
| Wk 3 | Stack interaction engine + product-scan warnings | 14 (M4), 15 (M5) |
| Wk 4 | Sprint 5a stack wiring, Sprint 6 deep links, Sprint 7 auth/OTA, Sprint 8 ship gate | 5a, 6, 7, 8 |

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

Foundation complete: 97 tests, 63 source files, 21 commits. All screens scaffolded, all core logic built and tested. Code review complete (15 fixes). Schema migration + first-launch DB download wired. App runs on device with real Supabase data. Now: FitScore UI integration + stack wiring.

---

## NEXT UP

**Sprint 4 remaining (FitScore UI):**
- Integrate FitScore into product detail screen UI
- Build FitScore explanation UI (which profile factors affected score)
- Build "personalized for you" badge
- FitScore recalculation on profile change

**Sprint 5a remaining (Stack wiring):**
- Wire add-to-stack from product detail (trigger safety check first)
- Wire remove-from-stack with undo snackbar
- Supabase sync for stack changes (write local first)

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
- [x] Set up app_theme.dart with WCAG AA colors (light + dark), Inter typography, 8dp grid
- [x] Create crash_reporting_service.dart stub (Crashlytics or Sentry)
- [x] Create analytics_service.dart stub
- [x] Store profile in user_data.db user_profile table (DB persistence wiring)
- [x] Write profile persistence tests (read back from DB after save)
- [x] Splash screen (flutter_native_splash, brand color #0A7D6F, logo, 1.5s)
- [x] App icon design (teal shield, white checkmark/pill)
- [x] Design system: Inter font family + 8dp spacing grid

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

**Status:** DONE
**Timeline:** Week 3-4
**Completed:** 2026-04-08
**Note:** Most Sprint 1 tasks were completed during Sprint 0 build — SafeJson, ReferenceDataRepository, Drift DBs, Supabase client all done. Remaining items (offline indicator, freemium gating, guest mode, test fixtures, scan limit service) completed 2026-04-08.

### Tasks

- [x] SafeJson extensions for all JSON parsing (completed in Sprint 0)
- [x] ReferenceDataRepository with lazy-cached loaders (completed in Sprint 0)
- [x] CoreDatabase with 88-col products_core + query methods (completed in Sprint 0)
- [x] UserDatabase with profile, stack, favorites, cache tables (completed in Sprint 0)
- [x] Supabase client with env-var config (completed in Sprint 0)
- [x] SyncService with atomic DB swap + rollback (completed in Sprint 0)
- [x] DetailBlobService for on-demand fetch (completed in Sprint 0)
- [x] Offline mode indicator (header status bar: online/offline/syncing)
- [x] Freemium gating service (SharedPreferences for guest: 10 lifetime scans, Supabase user_usage for signed-in: 20/day)
- [x] Guest mode support (app usable without sign-in, limited features)
- [x] Create test fixtures directory with representative JSON blobs
- [x] Implement scan_limit_service.dart stub

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

**Status:** DONE
**Timeline:** Week 5-6
**Completed:** 2026-04-08

### Tasks

- [x] Build Home screen with modular widgets (SearchBar, StackHealth, RecentScans, ProfileCompleteness, CategoryChips)
- [x] Implement search screen with text input, empty state, clear button
- [x] Implement barcode scan screen with mobile_scanner, torch toggle, manual entry fallback
- [x] Implement category filter chips (omega-3, probiotic, multivitamin, collagen, adaptogen, nootropic)
- [x] Home screen greeting (time-based with nickname)
- [x] Profile completeness banner (shows when < 60%)
- [x] Search + scan + home widget tests (8 tests)
- [x] Wire FTS search to CoreDatabase (debounced 300ms, LIMIT 50, latest-query-wins) — LIKE-based searchProducts() since no FTS virtual table needed
- [x] Wire barcode scan to CoreDatabase.findByUpc() — ConsumerStatefulWidget with loading overlay
- [x] Implement recent searches (SharedPreferences-backed, max 10, deduplication)
- [x] Build product list/grid toggle view — list/grid toggle with result count header
- [x] Product not found flow (bottom sheet with UPC, "Scan Another" + "Search Instead" buttons)
- [x] Decision-first scan result (500ms verdict color flash + HapticFeedback.mediumImpact before navigation)

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

**Status:** DONE
**Timeline:** Week 7-8
**Completed:** 2026-04-08

### Tasks

- [x] Build product detail screen with instant header from products_core
- [x] Build ScoreBreakdownCard (4 section bars: Ingredient Quality /25, Safety /30, Evidence /20, Brand Trust /5)
- [x] Build InteractionWarnings widget (severity-sorted, evidence badges, clickable source URLs)
- [x] Build BlendWarningBanner (proprietary blend detection)
- [x] Build UnknownIngredientBanner (mapped_coverage < 0.5 warning)
- [x] BLOCKED product handling: no score displayed, red banner with reason + FDA source URLs
- [x] Shimmer loading for detail blob sections
- [x] Product detail tests: score breakdown (4 labels, values, null handling), interaction warnings (sorting, parsing)
- [x] Wire to real CoreDatabase provider — coreDatabaseProvider added to database_providers.dart, overridden at app startup in main.dart
- [x] Implement detail blob fetch + cache in user_data.db — 24h TTL via getCachedDetail()/cacheDetail(), Supabase fetch on miss
- [x] Build condition alert banner from interaction_summary_hint — amber _ConditionAlertBanner from SQLite field (no network needed)
- [x] Score education overlay ("What does this score mean?") — _ScoreEducationSheet modal explaining 4 pillars + verdicts
- [x] Better Alternatives section — BetterAlternativesSection widget using findAlternatives() same-category higher-scored products
- [x] Score ring animation — AnimationController 800ms easeOutCubic, Tween 0→score
- [x] Handle NOT_SCORED products — grey _NotScoredCircle with "N/A" and explanation text
- [x] Clinical citation links — url_launcher LaunchMode.externalApplication (no WebView needed)

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

## Sprint 9: Catalog Pipeline v3.4.x + v1.3.2 Schema

**Status:** DONE
**Timeline:** 2026-04-09 to 2026-04-11
**Completed:** 2026-04-11
**Repo:** Pipeline (peaceful-ritchie)

### Tasks

- [x] Sugar penalty B1_dietary_sugar_penalty wired into scorer
- [x] Nutrition hybrid model (calories_per_serving column + nutrition_detail blob)
- [x] Unmapped actives transparency (detail_blob.unmapped_actives with names/total/excluding_banned_exact_alias)
- [x] B0 immediate-fail config-driven penalties (high_risk + watchlist tiers)
- [x] L1 enrollment bands → config-driven (already done, verified)
- [x] L2 D4 high_standard_region promoted to object with accepted_regions list
- [x] L3 B0 high_risk and watchlist penalties read from config
- [x] R2 orphan flag probiotic_bonus_applies_before_ceiling deleted
- [x] A1_bioavailability_form.max raised 15 → 18 (stop compressing enricher's 0-18 raw score)
- [x] A2_premium_forms.max raised 3 → 5 (reward stackers)
- [x] omega3_dose_bonus.max raised 2 → 3 (restore pre-merge value)
- [x] omega3 bands retuned: prescription_dose 2→3, high_clinical 2→2.5, aha_cvd 1.5→2
- [x] B1_harmful_additives.cap raised 8 → 15 (5 critical additives now count fully)
- [x] probiotic_bonus _caps_note added for audit clarity
- [x] Legacy section_E_dose_adequacy synced with new omega3 values
- [x] Catalog rebuilt across 8 brands → 5,231 products, 0 errors, max A: 21 → 25, max score_80 ~50 → 68.5
- [x] release_catalog_artifact.py staging script with 9 validation gates
- [x] import_catalog_artifact.sh Flutter bridge with 10 validation gates
- [x] Catalog bundled into Flutter via Git LFS (assets/db/pharmaguide_core.db, 11.75 MB)
- [x] Supabase OTA round-trip: upload + manifest insert + anon-read verify (three-way checksum match)
- [x] Pre-existing API key leak: scrubbed from git history via interactive rebase

### Definition of Done

- All pipeline tests pass: `pytest scripts/tests/` → 3,259 passed, 4 skipped
- Real catalog max Section A reaches 25 (was 21 — ceiling now reachable)
- Three-way checksum match: pipeline dist / Supabase remote / Flutter bundled
- Score field naming frozen: `score_quality_80`, `score_display_100_equivalent` (no "section A-E" in exports)
- All scoring config changes have lockdown tests in TestShipNowConfigLockdown

### Definition of Done (verified)

- Pipeline test suite: 3,259/3,259 passed
- Catalog: 5,231 products, 100% coverage, 0 errors
- Supabase manifest current row: db_version=2026.04.11.040818, schema=1.3.2, products=5,231

### Commits

- Pipeline: `7569689` (B0 hardcoded values), `9e22aef` (probiotic bonus), `4b9fa2e` (probiotic+B0 hardening), `5ddbdfb` (dashboard fix), `601a8c1` (L2/L3/R2), `a4892a6` (v3.4.x recalibration)
- Flutter: `5717db0` (3 detail widgets), `8f6b68f` (catalog v2026.04.10.235036), `621d3f2` (catalog v2026.04.11.040818)

---

## Sprint 10: Stack Nutrient Safety (M1)

**Status:** DONE (service + provider + widgets + integration)
**Timeline:** 2026-04-11
**Completed:** 2026-04-11
**Repo:** Flutter (PharmaGuide ai)

### Tasks

- [x] StackNutrientAggregator (pure function, ~200 LOC) with defensive field-name fallback
- [x] StackUlChecker with 7-tier classification (noRda → exceedsUl) and 15 nutrient-specific warnings
- [x] NutrientTier enum + NutrientTotal/NutrientStatus value types
- [x] 21 aggregator tests (skip rules, field fallbacks, unit conflict, zinc stacking spec scenario)
- [x] 22 UL checker tests (every tier, demographic lookup, fuzzy name match, malformed data)
- [x] stackNutrientStatusesProvider FutureProvider that loads stack → blobs → aggregates → classifies
- [x] _detailBlobByDsldIdProvider with 24h cache TTL (matches product detail screen)
- [x] NutrientProgressBar widget (single-row, 7-tier color ladder, warning chip)
- [x] NutrientAccumulationPanel widget (header + alert badge + sorted rows)
- [x] 8 progress bar widget tests + 6 panel widget tests
- [x] Integrated into stack_screen.dart `_StackTab` (auto-collapses when stack is empty)
- [x] Full Flutter test suite: 204/204 passed
- [x] Dart analyze: zero issues on all 6 new files

### Definition of Done

- Aggregator handles every pipeline schema variant (mapped_name | canonical_id | standard_name | normalized_key)
- UL checker reads correct rda_optimal_uls.json field names (rda_ai, age_range, NOT the broken e1_dosage_calculator names)
- Anonymous users still get UL check via highest_ul fallback
- Unit conflicts flagged but NEVER silently converted
- Zinc stacking scenario from spec (52 mg from 3 products, 130% UL) fires red warning
- PHI rule preserved: medications stay local-only

### Commits

- Flutter: `9cd0fc8` (M1 service layer + 43 tests), `a5f2747` (M1 provider + widgets + integration + 14 tests)

### Pending polish (Sprint 17)

- [ ] Manual device QA on real iOS + Android (the 52 mg zinc red banner)
- [ ] Golden-image tests for the 7-tier color ladder (visual regression)
- [ ] "Complete your profile" prompt when ageBracket is null
- [ ] Tap-to-expand contributions row in the progress bar

---

## Sprint 11: Interaction DB Pipeline (M2)

**Status:** READY
**Timeline:** Week 2 of next month
**Repo:** Pipeline
**Spec:** `docs/INTERACTION_DB_SPEC.md` v2.1.0

### Tasks

- [ ] Create `scripts/data/curated_interactions/interactions_drafts_v0.json` from user's hand-drafted JSON
- [ ] Drop supp.ai dump into `scripts/data/suppai_import/` (5 files: cui_metadata, interaction_id_dict, sentence_dict, paper_metadata, meta)
- [ ] Build `scripts/data/drug_classes.json` (24 classes from RxClass API)
- [ ] Write `scripts/api_audit/verify_interactions.py` (~300 LOC) — JSON schema, dup detection, RXCUI verify, CUI verify, canonical_id mapping, drug class expansion, direction normalization, severity normalization (4-tier → 5-tier), Major+ evidence gate, PMID extraction
- [ ] Write `scripts/build_interaction_db.py` (~400 LOC) — load drafts + supp.ai + overrides, dedup, conflict resolution (more cautious wins), apply overrides, emit interaction_db.sqlite + manifest + audit report
- [ ] Write `scripts/ingest_suppai.py` — filter pairs by canonical_id mapping, prefer human studies, top 3 sentences per pair, NEVER ship paper_metadata.json
- [ ] Schema: interactions table + research_pairs table + drug_class_map + interaction_db_metadata, all 12 indexes per spec §6.4
- [ ] ≥20 tests for verify_interactions, ≥15 tests for build_interaction_db
- [ ] Live API integration tests (RxNorm + UMLS) gated on `--live` flag
- [ ] Blocked-build demo: deliberately broken Major+ entry must fail build
- [ ] Output size validation: interaction_db.sqlite < 10 MB
- [ ] Auto-enrich curated entries with supp.ai PMIDs at build time

### Definition of Done

- `python scripts/build_interaction_db.py` produces `scripts/dist/interaction_db.sqlite` with all curated entries verified
- supp.ai 59,096 pairs filter down to ~5–10k after canonical_id matching
- Every Major+ entry has at least one source URL or PMID
- CUI corrections logged to audit report (the Vit K vs Vit D bug we already spotted)
- Pipeline test suite stays green

### Dependencies

- User must paste curated JSON into `interactions_drafts_v0.json`
- supp.ai dump must be at `/Users/seancheick/Downloads/Supp ai DB/`
- UMLS API key in pipeline `.env` (already present)

---

## Sprint 12: Interaction DB Flutter Binding (M3)

**Status:** READY (blocked by Sprint 11)
**Timeline:** Week 2 of next month
**Repo:** Flutter

### Tasks

- [ ] `lib/data/database/tables/interactions_table.dart` (Drift, mirrors §6.4 schema)
- [ ] `lib/data/database/interaction_database.dart` with 5 public lookup methods: lookupByCanonicalId, lookupByRxcui, lookupByDrugClass, lookupPair, rxcuisForDrugClass, getMetadata
- [ ] `dart run build_runner build` to regenerate `.g.dart`
- [ ] Bundle `assets/db/interaction_db.sqlite` via Git LFS
- [ ] Add `assets/db/interaction_db_manifest.json` with version + checksum
- [ ] Extend `scripts/import_catalog_artifact.sh` to also bundle interaction DB with 5 new validation gates
- [ ] Drift code-gen passes
- [ ] All 5 lookup methods covered by unit tests against a fixture DB
- [ ] App startup loads bundled DB in <200ms

### Definition of Done

- Bundled interaction_db.sqlite passes integrity_check
- All required tables present (interactions, research_pairs, drug_class_map, interaction_db_metadata)
- Drift queries return expected rows for fixture data
- Flutter test suite stays green

---

## Sprint 13: Stack Interaction Engine (M4)

**Status:** READY (blocked by Sprint 12)
**Timeline:** Week 3 of next month
**Repo:** Flutter

### Tasks

- [ ] Add `effectType` (inhibitor | enhancer | additive | neutral) to `InteractionResult` model
- [ ] Extend `StackInteractionChecker` with two new methods: `checkMedicationInteractions` and `checkSupplementPairInteractions`
- [ ] New `lib/services/stack/stack_safety_report.dart` aggregating M1 nutrient statuses + stack interactions + medication interactions + category warnings
- [ ] New `lib/services/medications/rxnorm_api_service.dart` (NLM RxNorm REST client, 20 req/sec cap, in-memory LRU cache)
- [ ] New `lib/features/medications/medication_entry_screen.dart` with autocomplete + RxNorm + offline drug-class fallback
- [ ] New `lib/features/stack/widgets/stack_safety_banner.dart` rendering severity-tinted warnings
- [ ] PHI build-time assertion: grep test fails the build if `type='medication'` reaches any sync code path
- [ ] ≥15 tests per checker method, golden-path test for safety report aggregation
- [ ] Live RxNorm integration test

### Definition of Done

- User can enter a medication via autocomplete and it stores in `user_stacks_local` with `type='medication'` + `rxcui` + `drug_classes`
- Adding a fish oil to a stack containing warfarin fires the AVOID-tier interaction warning
- Adding a calcium product to a stack containing levothyroxine fires the absorption-interference warning
- All medication rows are unreachable from any Supabase sync path (verified by grep test)
- Flutter test suite stays green

---

## Sprint 14: Product Scan Interaction Warnings (M5)

**Status:** READY (blocked by Sprint 13)
**Timeline:** Week 3 of next month
**Repo:** Flutter

### Tasks

- [ ] New `lib/features/product_detail/widgets/interaction_warning_card.dart` (~180 LOC)
- [ ] On scan, query interaction DB for each ingredient's canonical_id
- [ ] Cross-reference against current stack medications + supplements
- [ ] Render warnings sorted by severity at the top of product detail
- [ ] Each warning shows: severity chip, "Because you're taking X", mechanism, management, expandable source URLs
- [ ] Widget tests for 0 / 1 / N warnings
- [ ] Integration test against real bundled interaction_db.sqlite fixture

### Definition of Done

- Scan a fish oil while warfarin is in stack → AVOID banner fires with bleeding risk message
- Scan a turmeric while aspirin is in stack → CAUTION banner fires
- Scan a clean product → no banner, no jank
- Flutter test suite stays green

---

## Sprint 15: Display Widgets — Form & Absorption / Why-this-score / Certifications / Pairs-with

**Status:** READY
**Timeline:** Week 1 of next month (parallel with M1 polish)
**Repo:** Flutter
**Note:** All four widgets surface data that's ALREADY in `detail_blob` — no pipeline changes required.

### Tasks

- [ ] **"Form & Absorption" widget** — surfaces `ingredients[].bio_score`, `matched_form`, `absorption %`, and `notes` so the user sees that magnesium glycinate (bio_score 14) absorbs better than oxide (bio_score 6). Data is already in the blob.
- [ ] **"Why this score" widget** — renders `score_bonuses[]` and `score_penalties[]` with their `id`, `label`, `score`, and `detail`. Data is already in the blob.
- [ ] **"Certifications" widget** — renders `certification_detail.third_party_programs.programs[]` (NSF Sport, USP Verified, etc.) as gold badges. Data is already in the blob.
- [ ] **"Pairs well with your stack" widget** — uses `synergy_cluster.json` (already bundled) to surface positive ingredient synergies against the user's current stack
- [ ] Each widget gets ≥4 tests (loading, empty, populated, edge case)
- [ ] Slot all four into `product_detail_screen.dart` between scoring sections and Better Alternatives
- [ ] Defer SVG rendering of certification logos to a later sprint (text + icon for v1.0)

### Definition of Done

- All four widgets render with real bundled data on at least 5 sample products
- Widgets gracefully hide when underlying field is empty
- No pipeline changes required (verified)
- Flutter test suite stays green

---

## Sprint 16: Heavy Metal Risk + Excipient Density (v1.4 features, optional ship)

**Status:** READY (deferred — only ship if Sprints 11-15 close early)
**Timeline:** Week 4 stretch
**Repo:** Both pipeline + Flutter

### Tasks

- [ ] New `scripts/data/heavy_metal_limits.json` reference file with Prop 65 / EPA / GOED limits for fish_oil, turmeric, kelp, rice_protein, cocoa, etc.
- [ ] New scorer section `B8_contaminant_risk` in safety & purity (or fold into B0 gate)
- [ ] New `lib/features/product_detail/widgets/heavy_metal_warning_card.dart`
- [ ] Excipient density calculator: parse `inactive_ingredients`, compute `active_mass_percent = sum(active_mg) / total_capsule_mg`
- [ ] New scorer micro-metric `A7_formulation_density` with 3 bands: ≥85% → +2, 60–85% → +1, <60% → 0
- [ ] New `lib/features/product_detail/widgets/excipient_density_card.dart`
- [ ] Catalog rebuild required after scorer changes

### Definition of Done

- Heavy metal warnings fire on at least 5 known-contaminated raw materials
- Excipient density visible on every scored product
- Pipeline test suite stays green

---

## Sprint 17: Tech Debt + Polish

**Status:** READY (parallel with all other sprints)
**Timeline:** Throughout next month
**Repo:** Flutter (mostly)

### Tasks

- [ ] **Fix pre-existing `e1_dosage_calculator.dart` bug** — it reads `entry['nutrient']` (should be `standard_name`), `group['age_bracket']` (should be `age_range`), `group['rda']` (should be `rda_ai`). Currently always falls through to `highest_ul`. This silently broke per-product RDA tier scoring. M1 documented it but did not fix. File is read by FitScoreService E1 calculator, so the fix has cascading test updates.
- [ ] **Manual device QA for M1** — physical iPhone + Android, real stack with 3 zinc products, verify the red banner fires
- [ ] **Golden-image tests** for nutrient progress bar in all 7 tiers (visual regression gate)
- [ ] **"Complete your profile" prompt** in nutrient panel header when `ageBracket == null` — drives onboarding completion
- [ ] **Tap-to-expand contributions** in progress bar showing which products contributed
- [ ] **Telemetry on UL breaches** — log locally only (privacy), expose via "Data export" in settings
- [ ] **Catalog rollback dashboard card** — surface the rollback backup count for ops visibility
- [ ] **Fix markdownlint warnings** in `docs/INTERACTION_DB_SPEC.md` (cosmetic, code-fence languages, table spacing)

### Definition of Done

- e1_dosage_calculator no longer falls through to highest_ul for users with profile data
- M1 panel passes manual QA on both platforms
- Golden tests catch any future color tier regression
- All Flutter tests stay green

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
- [2026-04-11] data: supp.ai is an evidence corpus, not a curated interaction set. 59,096 pairs are extractive sentences from PubMed with NO severity, mechanism, or management fields. Treat it as a secondary research_pairs table, not a warning source. (Root cause: assumed supp.ai matched the user's curated draft format)
- [2026-04-11] arch: Flutter detail_blob lives in Supabase Storage, not in the bundled SQLite. Any new feature reading detail_blob must be async and cache-first. The aggregator must stay sync; the loader provider handles async. (Root cause: spec assumed detail_blob was inline in pharmaguide_core.db)
- [2026-04-11] data: e1_dosage_calculator.dart reads field names that don't exist in rda_optimal_uls.json (`nutrient`, `age_bracket`, `rda`/`ai`). Real fields are `standard_name`, `age_range`, `rda_ai`. Always falls through to highest_ul, silently breaking per-product RDA tier scoring. (Root cause: pipeline schema drift between when the calculator was written and when the reference data was finalized; no contract test caught it)
- [2026-04-11] arch: PharmaGuide v1.3.x scoring max Section A is 21/25 in real data — ZERO products hit the ceiling. Raising A1 from 15 to 18 unblocked the compression and pushed top products from 21 → 25. The ceiling was never the bottleneck; the sub-cap math was. Always inspect distributions before changing maxes. (Root cause: spec proposed raising the section max without checking real-data ceilings)
- [2026-04-11] testing: Unit conflict detection in nutrient aggregation must NEVER silent-convert. First-seen unit wins for the sum, mismatched contributions stay in the list with `hasUnitConflict: true` flag. Silent mg-to-mcg conversion is exactly how medical-grade bugs ship. (Root cause: convenience-driven design temptation to "just convert")
- [2026-04-11] arch: Flutter already had Severity (5 tiers), InteractionResult model, StackInteractionChecker (119 LOC), and UserStacksLocal with `type='medication'` + `rxcui` + `drug_classes` columns BEFORE the v2.0 interaction spec was written. Always inspect existing primitives before specifying new ones. (Root cause: subagent wrote spec without reading the Flutter repo)
- [2026-04-11] security: Medications in `user_stacks_local` (type='medication') are PHI and must NEVER sync to Supabase. Enforce with a build-time grep test that fails the build if any sync code path reads rows with `type='medication'`. (Root cause: PHI is easy to leak by extending an existing sync path)

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
| 2026-04-08 | 0      | Sprint 0 FULLY DONE: app_theme.dart (WCAG AA), crash/analytics stubs, profile DB persistence + 8 tests, splash + icon config |
| 2026-04-08 | 1      | Sprint 1 DONE: offline indicator, freemium gating, guest mode, scan_limit_service, test fixtures (5 JSON blobs) |
| 2026-04-08 | 2      | Sprint 2 DONE: searchProducts() LIKE query wired (300ms debounce, latest-query-wins), scanner→findByUpc() wired, recent searches (SharedPreferences), list/grid toggle, product-not-found bottom sheet, verdict flash + haptic |
| 2026-04-08 | 3      | Sprint 3 DONE: coreDatabaseProvider wired at startup, detail blob 24h cache, condition alert banner, score education overlay, BetterAlternatives, 800ms score ring animation, NOT_SCORED grey circle, citation links via url_launcher |
| 2026-04-08 | --     | **TOTAL: 97 tests passing, 57 source files, 0 analysis issues**                                                 |
| 2026-04-08 | --     | Code review: 15 fixes (3 critical, 5 high, 6 medium, 4 low). Hardcoded colors→AppTheme.brandTeal, AppColors.of(context) for dark mode, unified scoreColor thresholds, narrowed catch clauses, const constructors, strict analysis_options.yaml |
| 2026-04-08 | --     | Schema resilience: 26 missing v1.3.0 columns added via _ensureV130Columns() migration. All integer flags now nullable. Pipeline DB has 61 cols, Drift defines 88 — migration bridges the gap. |
| 2026-04-08 | --     | First-launch fix: SyncService corrected bucket (pharmaguide) + versioned path from export_manifest. main.dart downloads core DB on first launch if missing. App tested on simulator with 783 live products from Supabase. |
| 2026-04-08 | --     | Infra: iOS Podfile platform set to 13.0 + minimum deployment target enforced. dart fix --apply (24 const fixes). Polished README pushed to github.com/seancheick/Pharmaguide.ai |
| 2026-04-09 | --     | Pipeline v1.3.0 → v1.3.2 export schema: sugar penalty wired into B1, nutrition hybrid model (calories_per_serving column + nutrition_detail blob), unmapped actives transparency. Three new Flutter detail widgets (NutritionPanel, RefillReminderCard, UnmappedActivesDisclosure) with 39 widget tests. |
| 2026-04-10 | --     | Catalog rebuild + LFS bundle: 5,231 products across 8 brands, 11.79 MB pharmaguide_core.db committed via Git LFS to Flutter assets/db/. release_catalog_artifact.py (9 gates) + import_catalog_artifact.sh (10 gates) bridge scripts. API key leak scrubbed from git history via interactive rebase. |
| 2026-04-10 | --     | Pipeline backlog cleanup (L1, L2, L3, R2): config-driven D4 high_standard_region with accepted_regions list, B0 high_risk and watchlist penalties from config, orphan probiotic_bonus_applies_before_ceiling flag deleted. 10 new lockdown tests in TestShipNowConfigLockdown / TestD4HighStandardRegionConfigLockdown / TestB0ConfigDrivenPenalties / TestR2OrphanFlagRemoved. |
| 2026-04-11 | 9      | **Sprint 9 DONE: v3.4.x scoring recalibration** — A1.max 15→18 (stop compressing enricher's 0-18 raw score), A2.max 3→5, omega3.max 2→3 with band redistribution, B1 cap 8→15, probiotic_bonus _caps_note. Real-data impact: max Section A 21→25 (ceiling now reachable), max score_80 ~50→68.5 (+37%). 11 cascade test updates + 7 new lockdown tests. **3,259 pipeline tests passing.** |
| 2026-04-11 | --     | Supabase OTA round-trip verified end-to-end: upload pharmaguide_core.db v2026.04.11.040818 to bucket, insert export_manifest row with is_current=true, anon-read returns new manifest, storage HEAD returns SQLite magic bytes. **Three-way checksum match: pipeline dist / Supabase remote / Flutter bundled** all carry sha256:67ac3cdd...634fb1. |
| 2026-04-11 | --     | docs: INTERACTION_DB_SPEC.md v2.0 (978 → 1054 lines) full rewrite with Next-Agent Start-Here block, M1-M5 build order, and reuse list of 5 existing Flutter primitives (Severity enum, InteractionResult, StackInteractionChecker, UserStacksLocal, E1DosageCalculator). Then v2.1.0 (1140 lines) corrected supp.ai understanding: it is an evidence corpus (4,910 entities + 59,096 pairs from PubMed), NOT a curated interaction set. Two-tier data model: curated `interactions` table + supp.ai `research_pairs` table. |
| 2026-04-11 | 10     | **Sprint 10 DONE: M1 Stack Nutrient Safety** — Service layer (StackNutrientAggregator + StackUlChecker + models, ~600 LOC) with 43 tests. Riverpod glue (`stackNutrientStatusesProvider` with 24h cache TTL, _detailBlobByDsldIdProvider). NutrientProgressBar widget (7-tier color ladder, warning chip) + NutrientAccumulationPanel widget (sorted by severity, alert badge) with 14 widget tests. Integrated into stack_screen.dart `_StackTab`. **204 Flutter tests passing**, 0 analyzer issues. Closes the biggest medical-grade gap: per-stack UL totals. |
| 2026-04-11 | --     | Sprints 9-17 added to tracker. **Target: complete Sprints 4–15 by 2026-05-11 (4 weeks)** for V1.0 ship readiness. Wk1: M1 polish + display widgets + FitScore UI. Wk2: M2+M3 (interaction DB pipeline + Flutter binding). Wk3: M4+M5 (stack interaction engine + product-scan warnings). Wk4: Sprint 5a stack wiring + Sprint 6 deep links + Sprint 7 auth/OTA + Sprint 8 ship gate. |
| 2026-04-08 | --     | **TOTAL: 97 tests passing, 63 source files, 0 analysis errors, 21 commits** |
