# v2 Audit Backlog — surfaces still on pre-v2 styling

Sean 2026-05-15: as we move through Phase 11 production wiring, queue
every production surface that still carries old Material / default
styling here. Goal: no orphaned screens, no outdated surfaces, no
"old app vs new app" feel after the polish pass completes.

These are reskin / retokenize / typography-tighten work — not redesigns.
Same logic, same flows, same enums, same providers. Just the v2 voice.

**2026-05-16 update:** The 11.7L cluster cleared the top-priority
screens (Search / QuickCheck / MedicationEntry / ProfileSetup) plus
the two Stack conditional surfaces (TimingAdvice / Depletion) and
the Better Alternatives product-logic bug. Done items moved to the
✅ DONE block below with their commit refs. Open items stay
unchecked in their original sections.

---

## ✅ DONE — Phase 11.7L cluster (delivered 2026-05-16)

| Item | Phase | Commit(s) |
|---|---|---|
| Better Alternatives ranker (audience + tier + tiebreaker) | 11.7L.F | `d4f32c0`, `fd73f93`, `6d69fc5` |
| Better Alternatives loading skeleton + null-score fix (Vinpocetine) | 11.7L.F follow-up | `fd73f93`, `6d69fc5` |
| ProfileSetup v2 — dashboard + first-time wizard + None sentinels | 11.7L.B | `2430b06`, `c0f8f5a`, `4d9985b`, `153a592` |
| MedicationEntry v2 + snackbar-after-pop bug fix | 11.7L.E.1 | `f8c60e9` |
| Search v2 + on-market-first ordering | 11.7L.E.2 | `87cba3e` |
| QuickCheck v2 + structured result card | 11.7L.E.3 | `68b8b6d` |
| Stack v2 TimingAdvice card (legacy retint → cream + accent stripe) | 11.7L.C | `29a7caa` |
| Stack v2 Depletion card (legacy retint → cream + severity stripe) | 11.7L.C | `29a7caa` |
| Card copy polish: pluralize timing title, "Coverage looks good" | 11.7L.C fixups | `ec793dc` |
| Sentry sweep — 26 historical issues resolved + debug-noise filter | 11.7L.D | `d862c57` |
| App icon (cream brand mark) | 11.7L.A | `a37aeab` |
| Brand-cap fix: iOS/Android display labels → `PharmaGuide` | 11.7g.3.brand | `1f0fc70` |
| Canonical App Store description + pubspec sync | 11.7g.3.brand | `c43612f` |
| TestFlight 1.0.0+3 readiness doc + IPA build | 11.7g.3.e | `ec793dc` + (build) |

---

## Major lighthouse screens — covered

- [x] Home — Phase 11.1 (route swapped; gaps below)
- [x] Settings / Profile — Phase 11.0 + 11.7L.B (ProfileSetup hybrid)
- [x] Stack — Phase 11.2 + 11.7L.C (TimingAdvice + Depletion landed; gaps below)
- [ ] Scanner — Phase 11.8 (BLOCKED on Product Detail v2 TestFlight pass)
- [x] Product Detail — Phase 11.7 wired (toggle-gated; TestFlight 1.0.0+3 pending)
- [x] Auth invitation — fully wired + production route added (Phase 11.7i, `8e5f7da`)
- [x] Splash v2 — production route swapped (Phase 11.7i, `8e5f7da`)
- [x] Onboarding v2 — production route swapped (Phase 11.7i, `8e5f7da`)
- [x] Search — Phase 11.7L.E.2 (toggle-gated)
- [x] Quick Check — Phase 11.7L.E.3 (toggle-gated)
- [x] Medication Entry — Phase 11.7L.E.1 (toggle-gated + snackbar bug fix)
- [x] ProfileSetup (editor) — Phase 11.7L.B (toggle-gated; dashboard + wizard)

## Phase 11 known feature gaps (must close before TestFlight default flip)

The route swaps in 11.0–11.2 dropped some conditional production
surfaces that aren't yet mirrored in v2. These are SILENT regressions
for users in the "Optimal" state, but real risks for users with
warnings / recalls / nudges. Close before flipping defaults on for
production.

### Home v2 (Routes.home) — missing vs HomeScreen
- [ ] iOS CupertinoSliverRefreshControl pull-to-refresh
- [ ] Android RefreshIndicator wrap
- [ ] isFirstLaunchHomeProvider gate (first-launch UI subset)
- [ ] showExpandedSections conditional rendering
- [ ] HomeCitationStrip with real catalog count + last-updated
      timestamp (currently uses locked PGTransparencyFooter)
- [ ] Real Recent scans data from `_recentScansProvider`
      (currently fixture)

### Stack v2 (Routes.stack) — missing vs StackScreen
- [ ] _RecallAlertSlot — danger banner for recalled ingredients
      ★ HIGH PRIORITY: this is a safety surface
- [ ] _StackSafetyBannerSlot — aggregated safety warnings
      ★ HIGH PRIORITY: safety surface
- [ ] _ProfileNudgeSlot — "complete your profile" gentle nudge
- [x] _TimingAdviceSlot — done in 11.7L.C (`29a7caa`), v2 mirror w/ cream + accent stripe
- [x] _DepletionSlot — done in 11.7L.C (`29a7caa`), v2 mirror w/ 3-state stripe
- [ ] NutrientAccumulationPanel (production version with real data;
      v2 Nutrients tab uses fixture)
- [ ] _StackEmptyView (production empty state — calmer "Build your
      stack" CTA; v2 falls back to fixture items when empty)
- [ ] PGFrostedAppBar scroll-fade behavior (v2 uses plain AppBar
      currently)
- [ ] Pull-to-refresh (production has RefreshIndicator wrap)
- [ ] StackIntelligenceEngine status tier (currently hardcoded
      "Optimal")

### Settings v2 (Routes.profile) — missing vs SettingsScreen
- [ ] Email caption uses real Supabase user.email (currently
      "sean@example.com" fixture)
- [ ] _PrivacyDashboardSheet
- [ ] Real theme picker, real notifications toggle, real analytics
      toggle wiring

## Production paths still on legacy styling

These need v2 swaps before the polish pass closes. Order rough:

### Top-priority screens (high traffic) — DONE in 11.7L.E cluster
- [x] `features/quick_check/quick_check_screen.dart` → mirror in
      `features/quick_check/v2/quick_check_v2_screen.dart`
      behind `USE_V2_QUICK_CHECK` (11.7L.E.3, `68b8b6d`)
- [x] `features/search/search_screen.dart` → mirror in
      `features/search/v2/search_v2_screen.dart` behind
      `USE_V2_SEARCH` (11.7L.E.2, `87cba3e`)
- [x] `features/medications/medication_entry_screen.dart` → mirror
      in `features/medications/v2/medication_entry_v2_screen.dart`
      behind `USE_V2_MEDICATION_ENTRY` (11.7L.E.1, `f8c60e9`)

### Onboarding-adjacent
- [x] `features/profile/profile_setup_screen.dart` → hybrid
      dashboard + first-time wizard behind `USE_V2_PROFILE_SETUP`
      (11.7L.B, `2430b06` → `153a592`)
- [x] `features/onboarding/onboarding_screen.dart` (legacy) —
      swapped Phase 11.7i (`8e5f7da`)
- [x] `features/splash/animated_splash_screen.dart` (legacy) —
      swapped Phase 11.7i (`8e5f7da`)

### Scanner-adjacent — DEFERRED to Phase 11.8
- [ ] `features/scanner/camera_permission_gate.dart` — legacy gate
      wraps the scanner; v2 version exists at
      `features/scanner/v2/camera_permission_v2_screen.dart`
- [ ] `features/scanner/manual_barcode_sheet.dart` — bottom sheet
      that opens from the scanner's manual-entry button

### Modals + sheets
- [ ] Recall alert modal (in product detail flow)
- [ ] Safety report bottom sheet (Stack)
- [ ] "Show all" recents bottom sheet (`features/home/widgets/
      home_recent_scans.dart` → `_RecentScansSheet`)
- [ ] Privacy dashboard sheet (`features/settings/settings_screen
      .dart` → `_PrivacyDashboardSheet`)
- [ ] Share-clinician-report modal (`features/stack/widgets/
      share_clinician_report_button.dart`)

### Dialogs + confirmations
- [ ] Stack delete confirmation (currently Material SnackBar Undo —
      may stay if it matches v2 voice on review)
- [ ] Generic error dialogs across feature screens

### Empty + loading + error states
- [ ] Stack empty view (`features/stack/stack_screen.dart` →
      `_StackEmptyView`) — production version; v2 wishlist tab
      already has a mirror but stack-empty needs its own surface
- [ ] Recent scans empty (Home) — production version uses Material
      PGCard `recessed` variant
- [x] Search no-results — done in 11.7L.E.2 (`87cba3e`); v2
      `PGEmptyState` with "No match found" + class-fallback CTA
- [ ] Catalog unavailable screen (`app.dart` → `CatalogUnavailableScreen`)
- [ ] Various PGShimmerBox usages embedded in legacy widgets

### Deferred — bigger card widgets — DONE in 11.7L.C
- [x] `features/stack/widgets/timing_advice_card.dart` — v2 mirror
      at `features/stack/v2/widgets/pg_timing_advice_card.dart`
      (`29a7caa`). Legacy widget retained until Phase 11.11 cleanup.
- [x] `features/stack/widgets/depletion_checker_card.dart` — v2
      mirror at `features/stack/v2/widgets/pg_depletion_card.dart`
      (`29a7caa`). Legacy widget retained until Phase 11.11.

### Smaller components still on legacy
- [ ] `core/widgets/pg_frosted_app_bar.dart` — frosted bar used by
      Stack screen, scroll-fade good but tone needs v2 tinted
      variant (similar to PGFrostedNavBar's `useV2Tones: true`)
- [ ] `core/widgets/pg_search_field.dart` — used in HomeSearchLauncher
- [ ] `features/home/widgets/home_citation_strip.dart` → calls
      `PGCitationStrip` (used outside home too) — needs v2 retint
- [ ] `features/stack/widgets/nutrient_accumulation_panel.dart` (the
      production version — v2 Stack already has its own Nutrients
      tab mirror, but production widget still legacy)
- [ ] `features/stack/widgets/nutrient_progress_bar.dart`
- [ ] `features/stack/widgets/stack_safety_banner.dart`

---

## How to use this list

When a production wiring commit lands for one of the major screens,
remove related entries from "Top-priority screens." When a modal /
sheet / dialog gets a v2 pass, check it off. Add new entries
discovered along the way.

Anything checked off can move to the ✅ DONE section at the top
with a commit reference. Don't delete — the audit trail matters
for the Phase 11.11 cleanup pass (we need to know which legacy
widgets are safe to remove and which still have v1 consumers).

---

## Product-logic bugs (separate track — NOT v2 styling)

These are recommendation/scoring/logic issues that need their own
dedicated fix sprint. They were surfaced during v2 wiring but DO NOT
block route swap — they exist in production already and v2 renders
the same (faithful) output.

### [x] Better Alternatives — recommendation relevance (Phase 11.7L.F)

**Status:** Shipped 2026-05-16 — commits `d4f32c0`, `fd73f93`,
`6d69fc5`. See `knowledge/better-alternatives-audit.md` for the
full audit + ranking formula.

**Summary of what landed:**

1. New pure module `lib/services/recommendations/
   better_alternatives_ranker.dart` with `rankAlternatives(current,
   candidates, {userGoals, limit})`. Hard filters (off-market,
   strictly higher score, no banned/recalled, audience walls)
   followed by a 4-tier classifier (supplement_type + ingredient
   family / supplement_type / ingredient family / primary_category
   fallback) and a 6-criterion tiebreaker chain (family Jaccard,
   goals Jaccard, score, mapped_coverage, brand_trust, allergen
   compatibility).
2. New pure module `lib/services/recommendations/
   audience_classifier.dart` — regex-based audience inference
   (kids / prenatal / mens / womens / senior / sport / general)
   with hard walls for kids + prenatal cross-recommendations.
3. New DB query `CoreDatabase.fetchBetterAlternativesPool(current)`
   that returns a wider 50-candidate pool with SQL-side hard filters
   (on-market, score > current, no banned/recalled, category OR
   supplement_type match).
4. Both `BetterAlternativesSection` widgets (v1 + v2) migrated to
   the new pipeline. Legacy `findAlternatives` marked `@Deprecated`.
5. **Vinpocetine null-score fix** — blocked products like
   dsld 16012 (FDA-banned, `score_quality_80 = NULL`) used to
   render an empty section because every candidate was rejected
   by the score comparison. Now: when current is unscored, any
   scored on-market non-blocked candidate is allowed through. A
   "do not rewrite this" comment guard sits at the policy site
   plus a pinned regression test (Phase 11.7L.F.fixups, `6d69fc5`).
6. **Loading skeleton + title rename** — `PGBetterAlternativesSkeleton`
   keeps the sticky-CTA scroll anchor on a real surface during
   fetch. Title changed from "Higher quality alternatives" →
   **"Similar higher-quality options"** to reflect that the ranker
   now mixes strict-quality with intent/family/audience match.
7. **28 new tests** (13 audience + 15 ranker) including 5 pinned
   regression cases by real dsld_id (Staminol 315814, Vit A 19170,
   GNC Probiotic 1646, Kids Multi 178559, Vinpocetine 16012).
   Each test asserts the legacy buggy recommendation NO LONGER
   surfaces AND the new top pick passes a sanity property.

See `knowledge/better-alternatives-audit.md` for the live-DB
queries that produced the 5 pinned bad examples + the worked
formula.

---

## Outstanding product-logic work (none currently blocking)

If you discover a recommendation / scoring bug during the
TestFlight walkthrough or after default flip, add it under a new
heading here with severity, symptom, root cause, and worked
examples. The Better Alternatives entry above is the template.
