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
**Current Sprint:** Sprint 0
**Overall Status:** IN PROGRESS

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

**Sprint 0: Foundation + Profile Setup** (Week 1-2)
Status: IN PROGRESS

Key objectives:
- Flutter project scaffolding with Riverpod 3.x, GoRouter, Drift
- Core constants (severity, colors, schema IDs) and models (InteractionResult, FitScoreResult, StackSafetyScore)
- Both Drift databases created (pharmaguide_core.db + user_data.db)
- Theme system (light + dark) with WCAG AA colors
- Five-tab shell navigation
- Supabase client initialized
- Splash screen + app icon
- Profile setup flow (conditions, drug classes, allergens)

---

## NEXT UP

**Sprint 1: Database + Core Services** (Week 3-4)
- Reference data repository + JSON helpers
- Offline mode indicator
- Freemium gating service (guest: 10 scans, free: 20/day)
- Supabase sync service
- Guest mode support

**Sprint 2: Product Catalog + Search** (Week 5-6)
- FTS search with 300ms debounce, LIMIT 50, latest-query-wins
- Modular home screen widgets (SearchBar, StackHealth, RecentScans, ProfileCompleteness)
- Product card with verdict badges
- Barcode scan flow (camera permissions, UPC lookup)
- Product not found submission flow
- Decision-first scan result (color flash + haptics)

**Sprint 3: Product Detail + Score Transparency** (Week 7-8)
- Result screen with score ring, verdict banner, grade
- Section score cards (Ingredient Quality, Safety, Evidence, Brand Trust)
- Detail blob fetch + cache + shimmer states
- BLOCKED product handling: no score, red banner with FDA links
- Score education overlay
- Better Alternatives section
- Interaction warnings with severity + evidence + clickable PMIDs

---

## Sprint 0: Foundation + Profile Setup

**Status:** NOT STARTED  
**Timeline:** Week 1-2  
**Effort estimate:** 15-25 pts

### Tasks

- [ ] Initialize Flutter project with correct package name and bundle ID
- [ ] Configure pubspec.yaml with all V1.0 dependencies (riverpod, go_router, drift, supabase_flutter, mobile_scanner, share_plus, cached_network_image, background_downloader, flutter_local_notifications, lucide_icons)
- [ ] Set up app_theme.dart with light + dark mode (colors, typography, shadows, spacing -- no colors outside theme)
- [ ] Set up GoRouter with ShellRoute for five tabs (Home, Scan, Stack, Chat, Profile)
- [ ] Create reference_db.dart (Drift schema for pharmaguide_core.db -- read-only)
- [ ] Create user_db.dart (Drift schema for user_data.db -- read/write)
- [ ] Create db_asset_loader.dart to load bundled pharmaguide_core.db from assets
- [ ] Create supabase_client.dart with initialization
- [ ] Create crash_reporting_service.dart stub (Crashlytics or Sentry)
- [ ] Create analytics_service.dart stub
- [ ] Create reference_data_cache.dart (load reference_data table once at startup)
- [ ] Create taxonomy_service.dart with debug asserts for condition/drug class counts
- [ ] Build profile setup flow: conditions checklist (14 conditions from clinical_risk_taxonomy)
- [ ] Build profile setup flow: drug class checklist (9 drug classes)
- [ ] Build profile setup flow: allergen selection (Big 8)
- [ ] Build profile setup flow: basic info (age range, biological sex for dosing)
- [ ] Store profile in user_data.db user_profile table
- [ ] Create main.dart + app.dart with proper initialization order
- [ ] Write database schema tests (verify tables exist, columns match export schema)
- [ ] Write profile persistence tests
- [ ] Splash screen (flutter_native_splash, brand color #0A7D6F, logo, 1.5s)
- [ ] App icon design (teal shield, white checkmark/pill)
- [ ] Design system: WCAG AA color palette (light + dark mode tokens)
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

**Status:** NOT STARTED  
**Timeline:** Week 3-4  
**Effort estimate:** 15-22 pts

### Tasks

- [ ] Implement ScoreFitCalculator (local-only, never persisted, computes from profile + product data)
- [ ] Write ScoreFitCalculator tests: profile with no conditions, single condition, multiple conditions, all drug classes, edge cases (null scores, NOT_SCORED products)
- [ ] Create sealed Warning type hierarchy (banned_ingredient, recalled_ingredient, harmful_additive, allergen_risk, dose_exceeded, interaction_warning)
- [ ] Create DetailBlob model with @JsonKey annotations (use `notes` NOT `reference_notes`)
- [ ] Create SafeJson extensions for all JSON parsing (never raw Map casting)
- [ ] Create product_core.dart model matching products_core schema
- [ ] Create health_profile.dart model
- [ ] Build parser smoke tests with fixtures: SAFE product, BLOCKED product, NOT_SCORED product, product with PDF image URL, product with interaction_summary
- [ ] Implement TaxonomyService with exactly 14 conditions + 9 drug classes from clinical_risk_taxonomy
- [ ] Write TaxonomyService tests verifying exact condition/drug class counts and IDs
- [ ] Implement scan_limit_service.dart stub (guest: 10 scans lifetime, signed-in: 20/day)
- [ ] Create test fixtures directory with representative JSON blobs
- [ ] Offline mode indicator (header status bar: online/offline/syncing)
- [ ] Freemium gating service (Hive for guest: 10 lifetime scans, Supabase user_usage for signed-in: 20/day)
- [ ] Guest mode support (app usable without sign-in, limited features)

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

**Status:** NOT STARTED  
**Timeline:** Week 5-6  
**Effort estimate:** 18-26 pts

### Tasks

- [ ] Implement FTS search screen with 300ms debounce
- [ ] Implement latest-query-wins pattern (cancel stale queries)
- [ ] Enforce LIMIT 50 on all search queries
- [ ] Build search result list with verdict badge, score, brand name
- [ ] Implement recent searches (Hive local storage)
- [ ] Build Home screen with carousels (top-rated in category, trending)
- [ ] Implement barcode scan screen with camera permissions
- [ ] Integrate mobile_scanner for UPC reading
- [ ] Implement UPC lookup against products_core (handle collisions: multiple products same UPC)
- [ ] Build product list/grid toggle view
- [ ] Implement category filter chips (omega-3, probiotic, multivitamin, etc. from primary_category)
- [ ] Write search tests: empty query, partial match, no results, special characters
- [ ] Write scan tests: valid UPC, unknown UPC, camera permission denied
- [ ] Product not found flow (submission modal with photo + manual entry)
- [ ] Decision-first scan result (color flash + haptic feedback on scan)
- [ ] Home screen as modular widgets (SearchBar, StackHealth, RecentScansCarousel, ProfileCompleteness)

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

**Status:** NOT STARTED  
**Timeline:** Week 7-8  
**Effort estimate:** 20-28 pts

### Tasks

- [ ] Build result screen with score ring animation (score_100_equivalent)
- [ ] Implement verdict banner (SAFE=green, CAUTION=amber, POOR=orange, UNSAFE=red, BLOCKED=red+icon)
- [ ] Implement grade display (Exceptional through Very Poor)
- [ ] Build B0 gate screen (banned/recalled hard-stop -- no score ring, no grade, just warning)
- [ ] Handle NOT_SCORED products (no ring, no grade, explanation text)
- [ ] Build Card 1: Ingredient Quality (max 25, sub-scores, premium forms, bioavailability)
- [ ] Build Card 2: Safety & Purity (max 30, contaminants, allergens, dose safety)
- [ ] Build Card 3: Evidence & Research (max 20, clinical backing, strength of evidence)
- [ ] Build Card 4: Brand Trust (max 5, manufacturer reputation, certifications)
- [ ] Build Card 5: Dose Adequacy (additive, EPA/DHA context for omega-3)
- [ ] Implement detail blob fetch from Supabase Storage (hashed path via detail_blob_sha256)
- [ ] Build shimmer loading states for detail blob sections
- [ ] Implement detail cache in user_data.db (LRU, max budget, invalidate on version mismatch)
- [ ] Build condition alert banner from interaction_summary_hint (instant, from SQLite)
- [ ] Build full interaction_summary display after detail blob hydration
- [ ] Implement dose_threshold_evaluation display (B7: 150%+ UL warnings)
- [ ] Add clinical citation links (WebView for PMID URLs)
- [ ] Write widget tests for all verdict states
- [ ] Write widget tests for B0 gate
- [ ] Write integration test for scan-to-detail flow
- [ ] Score education overlay ("What does this score mean?")
- [ ] BLOCKED product handling: no score displayed, red banner with reason + FDA links
- [ ] Better Alternatives section (similar products with higher scores)

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

**Status:** NOT STARTED  
**Timeline:** Week 9-10  
**Effort estimate:** 18-24 pts

### Tasks

- [ ] Integrate ScoreFitCalculator into product detail screen
- [ ] Display FitScore (0-100) alongside pipeline score
- [ ] Build FitScore explanation UI (which profile factors affected score)
- [ ] Implement profile-driven condition/drug interaction warnings
- [ ] Build "personalized for you" badge when FitScore differs significantly from base score
- [ ] Implement FitScore recalculation on profile change (never persisted, always fresh)
- [ ] Build FitScore comparison view (side-by-side two products for same profile)
- [ ] Handle edge cases: no profile set, partial profile, profile with all conditions
- [ ] Write FitScore calculation tests with diverse profile combinations
- [ ] Write UI tests for FitScore display states

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

**Status:** NOT STARTED  
**Timeline:** Week 11-12  
**Effort estimate:** 16-22 pts

### Tasks

- [ ] Build Stack screen (list of user's current supplements)
- [ ] Implement add-to-stack from product detail
- [ ] Implement remove-from-stack with confirmation
- [ ] Build stack local-first storage in user_data.db (user_stacks_local)
- [ ] Implement Supabase sync for signed-in users (write local first, sync on connectivity)
- [ ] Build offline queue (Hive) for stack changes -- flush on reconnect
- [ ] Implement LWW (Last Write Wins) conflict resolution with client_updated_at
- [ ] Implement deleted_at tombstones for soft deletes
- [ ] Build stack summary view (total daily supplement load)
- [ ] Write sync tests: add while offline, sync on reconnect, conflict resolution
- [ ] Write stack persistence tests
- [ ] Stack wishlist sub-tab (My Stack | Wishlist)
- [ ] Full Stack Analysis report (nutrient breakdown, interactions, timing, goals, "What If" scenarios)
- [ ] Add-to-stack scheduling flow (time, supply tracking, reminders — all skippable)
- [ ] Undo after stack delete (5s snackbar)

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

**Status:** NOT STARTED  
**Timeline:** Week 12-13  
**Effort estimate:** 14-20 pts

### Tasks

- [ ] Build Stack Safety Score (separate from FitScore, 0-100 with hard-stop caps)
- [ ] Implement ingredient fingerprint cross-check across stack (duplicate detection)
- [ ] Build stimulant stacking detection (contains_stimulants flag across products)
- [ ] Build sedative stacking detection (contains_sedatives flag)
- [ ] Build blood thinner stacking detection (contains_blood_thinners flag)
- [ ] Implement interaction checking between stack products using interaction_checker.dart
- [ ] Build safety alert UI for stack-level warnings
- [ ] Build "safe to add?" check when adding new product to stack
- [ ] Handle edge case: empty stack, single product stack, 20+ product stack
- [ ] Write safety checker tests with known interaction pairs
- [ ] Write UI tests for safety alerts

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

**Status:** NOT STARTED  
**Timeline:** Week 14  
**Effort estimate:** 10-14 pts

### Tasks

- [ ] Build share card generator (product name, score, verdict, grade)
- [ ] Implement share_plus integration for native sharing
- [ ] Use pipeline-provided share_title, share_description, share_highlights
- [ ] Build Open Graph preview for shared links (share_og_image_url)
- [ ] Implement deep link handling for shared product links (app_links)
- [ ] Build "shared with you" entry point from deep link
- [ ] Handle deep link edge cases: app not installed, invalid product ID, expired link
- [ ] Write deep link routing tests
- [ ] Write share content generation tests
- [ ] Stack share ("Export PDF for Doctor", "Share List")

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

**Status:** NOT STARTED  
**Timeline:** Week 15  
**Effort estimate:** 14-20 pts

### Tasks

- [ ] Build Settings screen (notification preferences, data management, about)
- [ ] Build Profile edit flow (update conditions, drug classes, allergens)
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

| Version | Identity | Sprints | Key Features |
|---------|----------|---------|-------------|
| **V1.0** | Core Product | 0-8 | Scan, score, FitScore, stack safety, social sharing, full profile tab |
| **V1.1** | Medication Intelligence | 9-11 | RxNorm medication stack, StackSafetyEngine, depletion checker, product comparison |
| **V1.2** | Trust & Transparency | 12-13 | FitScore explanation layer, recompute strategy, trust layer UI, doctor PDF |
| **V2.0** | AI Intelligence | 14-19 | Gate-based AI chat, alternative suggestions, nutrient gap analysis, prescription OCR |
| **V2.1** | Engagement & Retention | 20-22 | Dose reminders, reorder alerts, starter stacks, FDA notifications, feedback loop |
| **V3.0** | Platform & Ecosystem | 23-27 | B2B REST API, white-label SDK, "Verified" badge, family profiles, practitioner portal |
| **V3.1** | Premium Intelligence | 28-30 | Lab integration, interaction matrix, clinical governance, drug-drug interactions |

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

| Date | Sprint | Change |
|------|--------|--------|
| 2026-04-07 | -- | Initial sprint tracker created |
