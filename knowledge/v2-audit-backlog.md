# v2 Audit Backlog — surfaces still on pre-v2 styling

Sean 2026-05-15: as we move through Phase 11 production wiring, queue
every production surface that still carries old Material / default
styling here. Goal: no orphaned screens, no outdated surfaces, no
"old app vs new app" feel after the polish pass completes.

These are reskin / retokenize / typography-tighten work — not redesigns.
Same logic, same flows, same enums, same providers. Just the v2 voice.

---

## Major lighthouse screens — covered

- [x] Home (Phase 11.1, partial — status tier wires next)
- [x] Settings / Profile (Phase 11.0)
- [x] Stack (Phase 11.2, partial — see Phase 11 known gaps below)
- [ ] Scanner — wiring next (Phase 11.3)
- [ ] Product Detail — wiring next (Phase 11.4)
- [x] Auth invitation — fully wired
- [x] Splash v2 — gallery only, production still legacy
- [x] Onboarding v2 — gallery only, production still legacy

## Phase 11 known feature gaps (must close before TestFlight)

The route swaps in 11.0–11.2 dropped some conditional production
surfaces that aren't yet mirrored in v2. These are SILENT regressions
for users in the "Optimal" state, but real risks for users with
warnings / recalls / nudges. Close before flipping useV2Theme on for
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
- [ ] _TimingAdviceSlot — timing optimization advice
- [ ] _DepletionSlot — nutrient depletion by medications
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

### Top-priority screens (high traffic)
- [ ] `features/quick_check/quick_check_screen.dart` — production
      Quick Check; production HomeQuickCheckCta routes here
- [ ] `features/search/search_screen.dart` — production search
      results + filters
- [ ] `features/medications/medication_entry_screen.dart` —
      production med-entry multi-step

### Onboarding-adjacent
- [ ] `features/profile/profile_setup_screen.dart` — multi-step
      profile creation (legacy SegmentedButton + Material chips)
- [ ] `features/onboarding/onboarding_screen.dart` (legacy) — swap
      with v2 version from `features/onboarding/v2/`
- [ ] `features/splash/animated_splash_screen.dart` (legacy) — swap
      with v2 version

### Scanner-adjacent
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
- [ ] Search no-results
- [ ] Catalog unavailable screen (`app.dart` → `CatalogUnavailableScreen`)
- [ ] Various PGShimmerBox usages embedded in legacy widgets

### Deferred — bigger card widgets (low visibility, not safety-critical)
- [ ] `features/stack/widgets/timing_advice_card.dart` — only renders
      when stack has timing optimizations; not safety-critical.
      Retint via `useV2Tones` flag (same pattern as PGSeverityBanner).
- [ ] `features/stack/widgets/depletion_checker_card.dart` — only
      renders when medications cause nutrient depletions. Same
      retint pattern.

### Smaller components still on legacy
- [ ] `core/widgets/pg_frosted_app_bar.dart` — frosted bar used by
      Stack screen, scroll-fade good but tone needs v2 tinted
      variant (similar to PGFrostedNavBar's `useV2Tones: true`)
- [ ] `core/widgets/pg_search_field.dart` — used in HomeSearchLauncher
- [ ] `features/home/widgets/home_citation_strip.dart` → calls
      `PGCitationStrip` (used outside home too) — needs v2 retint
- [ ] `features/stack/widgets/depletion_checker_card.dart`
- [ ] `features/stack/widgets/nutrient_accumulation_panel.dart` (the
      production version — v2 Stack already has its own Nutrients
      tab mirror, but production widget still legacy)
- [ ] `features/stack/widgets/nutrient_progress_bar.dart`
- [ ] `features/stack/widgets/timing_advice_card.dart`
- [ ] `features/stack/widgets/stack_safety_banner.dart`

---

## How to use this list

When a production wiring commit lands for one of the major screens,
remove related entries from "Top-priority screens." When a modal /
sheet / dialog gets a v2 pass, check it off. Add new entries
discovered along the way.

Anything checked off can move to a separate "Done" section if useful,
or just deleted — git history preserves the audit trail.

---

## Product-logic bugs (separate track — NOT v2 styling)

These are recommendation/scoring/logic issues that need their own
dedicated fix sprint. They were surfaced during v2 wiring but DO NOT
block route swap — they exist in production already and v2 renders
the same (faithful) output.

### [ ] Better Alternatives — recommendation relevance

**Severity:** Medium (trust-eroding; can recommend wrong-category
products with unrelated ingredients, undermining the "Higher quality
alternatives" promise).

**Symptom (Sean 2026-05-15):** Better Alternatives sometimes
surfaces products from the wrong category or with unrelated
ingredients. Feels unreliable.

**Current behavior:** `CoreDatabase.findAlternatives(category,
minScore=0.8*currentScore, excludeDsldId, limit=N)` —
`primary_category` exact match + higher `scoreQuality80` + sort by
score desc. That's it. No active-ingredient overlap check, no
intent/use-case alignment, no formulation-safety filter, no
fit-score awareness.

**Root cause:** `primary_category` in `pharmaguide_core.db` is too
coarse — a "Multivitamin" category includes products with very
different active-ingredient profiles. Sort-by-score-only also
ignores why the current product was downgraded, so the recommended
"better" alternative may share the same flaw at higher cosmetic score.

**Should prioritize (in order):**
1. **Same category** (primary_category exact — already doing this)
2. **Same intent / use case** — derive from active ingredients or
   product tags (e.g. "sleep support", "post-workout recovery",
   "iron deficiency"). Could lean on the goal-cluster mapping the
   FitScore engine already produces.
3. **Same key active ingredients** — overlap on the actives the
   user is actually shopping for (Magnesium → magnesium products,
   not generic multis that happen to contain it).
4. **Cleaner score/profile fit** — currently only score is filtered;
   should also prefer products whose FitDisplay is better for the
   active profile (FitStrongMatch / FitGoodMatch). Means
   alternative lookup needs to be fit-score-aware, not score-only.
5. **Safer formulation** — prefer products without proprietary
   blends, without unmapped actives, with third-party testing, in
   bioavailable forms (formulation pillar score).

**Affects:**
- `lib/data/database/core_database.dart` lines 308–334 —
  `findAlternatives` query needs new join/filter logic, OR a
  layered scoring fn on top of category match.
- `lib/features/product_detail/widgets/better_alternatives.dart` —
  production widget; v2 reuses the same DB query so the fix lands
  identically in both.
- May need a new column or sidecar table for active-ingredient
  fingerprint / goal-cluster tag.

**NOT a v2 visual issue** — both prod and v2 render the same
`findAlternatives` output. v2 wiring (S16 BetterAlternatives) is
faithful to production behavior including this flaw. The fix
belongs in a dedicated product-logic sprint, separate from v2
adapter work.

**Approach when scheduled:**
- Spec the new ranking signal stack (category > intent > active
  overlap > fit > formulation safety) with worked examples (a few
  products users have reported feel wrong).
- Add a goal-cluster column or compute it on the fly.
- Refactor `findAlternatives` to a two-stage pipeline:
  candidate generation (category + active overlap) → ranking
  (fit, formulation, safety, score).
- Add golden tests pinning the top-N for representative products
  so the next regression catches itself.
- Coordinate with FitScore engine — same fit math should drive both.
