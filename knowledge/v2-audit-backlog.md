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
- [ ] Stack — wiring in progress (Phase 11.2)
- [ ] Scanner — wiring next (Phase 11.3)
- [ ] Product Detail — wiring next (Phase 11.4)
- [x] Auth invitation — fully wired
- [x] Splash v2 — gallery only, production still legacy
- [x] Onboarding v2 — gallery only, production still legacy

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
