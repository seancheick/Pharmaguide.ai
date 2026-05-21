# v2 TestFlight Readiness — Build 1.0.0+4

**Status:** Walkthrough patches landed; 5 toggles still default false
**Branch:** `design/v2-mobile-polish`
**Date:** 2026-05-16 (1.0.0+4 cut at 13:30 PT)
**Predecessor:** 1.0.0+3 (walkthrough surfaced 11 bugs + 1 Sentry crash)

---

## What changed in 1.0.0+4 (vs 1.0.0+3)

Sean's real-device walkthrough on 1.0.0+3 found 11 bugs + 1 Sentry crash.
Six clusters landed in this build (commit `453aab7`). Cluster D (Quick
Check medication RxNorm) is punted to 1.0.0+5.

| Cluster | Bug | Status in 1.0.0+4 |
|---|---|---|
| **A** | 1 — Search bar not pinned + tap dead | Fixed (`SliverPersistentHeader` + `onTap` wired) |
| **A** | 2 — "Scan a supplement" CTA dead | Fixed (`context.go(Routes.scan)`) |
| **A** | 3 — "View Stack" dead | Fixed (`context.go(Routes.stack)`) |
| **A** | 10 — Stack app bar Add med / Share dead | Fixed (med routes to `/medication-entry`, Share uses production `ShareClinicianReportButton`) |
| **B** | 4 — Recent scan images placeholder | Fixed (provider now carries upc / imageThumbnailUrl / formFactor; renders via production `ProductImage`) |
| **B** | 7 — Stack fixture flash post-clear + swipe + tap | Fixed (fixtures only on initial load; empty state via `PGEmptyState`; tap-to-detail falls back to snackbar when dsldId missing) |
| **B** | 8 — "Feels mixed v1/v2" | Resolves once A+B+C land |
| **C** | 5b — QC suggestion score color missing | Fixed (`tierForScore` chip with tier color) |
| **C** | 6 — Med dosage accepts free text | Fixed (v1 + v2 default keyboard now numeric; users can still switch via 123↔ABC for "mg") |
| **E** | 11 — KSM-66 → Magnesium Glycinate | Fixed (`supplement_type` added to `_ensureV130Columns`) |
| **F** | 12 (Sentry) — Magic-link null-check | Fixed (`useRootNavigator: true` on showModalBottomSheet) |
| **G** | 9 — Other ingredients tap dead | Defensive (`useRootNavigator: true` on `PGModal.bottomSheet`) — needs your re-check |
| **D** | 5a — QC med search only finds supplements | **Deferred to 1.0.0+5** (RxNorm path needs integration) |

### What to re-check on 1.0.0+4

Same walkthrough flow as 1.0.0+3 — plus these targeted spot-checks:

1. **Home / search**: scroll the home feed. Search bar should stay
   pinned at the top under the status bar. Tap the search bar → opens
   /search (no more dead tap).
2. **Home / Scan CTA**: tap "Scan a supplement" → opens the camera.
3. **Home / Stack Health card**: tap anywhere on the card → opens
   the Stack tab.
4. **Home / Recent scans**: real product images should appear on the
   horizontal cards (was a green pill icon placeholder).
5. **Stack**: empty stack now shows "Your stack is empty" empty
   state — never the fixture brand names. Swipe-to-delete works on
   real rows. Tap a supplement card → opens product detail when the
   row has a dsldId, or shows a calm snackbar when it doesn't.
6. **Stack app bar**: + icon opens medication entry; share icon opens
   the clinician report share sheet.
7. **Medication entry**: dose field opens with the numeric keyboard
   by default (you can still switch to letters for "mg").
8. **Quick Check**: type a supplement name in either field — the
   suggestion's trailing score is now tinted (green / yellow / red
   per tier), not plain black.
9. **Product Detail / Other ingredients**: tap an individual inactive
   ingredient row — should open the FunctionalRolesSheet (v1 wiring
   was correct; defensive useRootNavigator fix in case iOS 26 was the
   culprit).
10. **Magic-link sign-in**: from the AuthInvitation screen, tap
    "Continue with email" — bottom sheet should open without crash
    (Sentry PHARMAGUIDE-W).
11. **Better Alternatives — KSM-66 Ashwagandha**: scan or open the
    KSM-66 product. "Similar higher-quality options" should NOT list
    Magnesium Glycinate (or any non-ashwagandha supplement). If it
    still does, the bundled catalog needs an OTA refresh to populate
    `supplement_type` — the migration column now exists but is NULL
    until the next catalog build lands.

---

## What's in this build

All five v2 visual mirrors land at once, each behind its own
`--dart-define` toggle. Logic, providers, drift schema, and the
matcher are unchanged from `main` — this build is a surface
overhaul plus four small behavioural fixes (one per phase).

| Phase | Toggle | Surface |
|---|---|---|
| **11.7g** | `USE_V2_PRODUCT_DETAIL=true` | Product Detail (18 sections, all wired) |
| **11.7L.B** | `USE_V2_PROFILE_SETUP=true` | ProfileSetup dashboard + first-time wizard (3-step) |
| **11.7L.E.1** | `USE_V2_MEDICATION_ENTRY=true` | MedicationEntry (RxNorm autocomplete + class fallback sheet) |
| **11.7L.E.2** | `USE_V2_SEARCH=true` | Catalog search w/ on-market-first ordering |
| **11.7L.E.3** | `USE_V2_QUICK_CHECK=true` | "Safe to take together?" pair check |

Beyond the toggled surfaces, the following v2 changes are **always
on** in this build (no env flag — already promoted in earlier
TestFlight cycles):

- Splash (v2 logo + animated underline, no tagline)
- Onboarding (4-step v2 editorial)
- Auth invitation (v2 magic-link + Apple/Google/skip)
- Home (v2 greeting w/ optional nickname, cream surfaces)
- Settings (v2 hairline groups, "Edit profile" routes to v2)
- Stack (v2 chrome + v2 TimingAdvice + v2 Depletion cards)
- App icon (splash brand mark on cream)

---

## Build command

```bash
make build-ipa-v2all SENTRY_ENVIRONMENT=testflight
```

Equivalent to:

```bash
flutter build ipa \
  $(DART_DEFINES) \
  --dart-define=USE_V2_PRODUCT_DETAIL=true \
  --dart-define=USE_V2_PROFILE_SETUP=true \
  --dart-define=USE_V2_MEDICATION_ENTRY=true \
  --dart-define=USE_V2_SEARCH=true \
  --dart-define=USE_V2_QUICK_CHECK=true \
  --dart-define=SENTRY_ENVIRONMENT=testflight \
  --release
```

After the IPA builds:

```bash
open "$(pwd)/build/ios/archive/Runner.xcarchive"
# Then in Xcode Organizer: Distribute App → App Store Connect → Upload.
```

See `knowledge/testflight-upload-handoff.md` for the full
Organizer walk-through (unchanged from the 1.0.0+2 cycle).

---

## Must-test user path on real device

Sean's stabilization walkthrough — do this once end-to-end before
inviting external testers. Each step lists the v2 surface that
must render and the behaviour to verify.

1. **Cold-boot splash** → cream background, no white flash, logo
   reveals over ~900ms, accent underline draws in + breathes.
2. **Onboarding** (only on fresh install / after a `flutter clean`
   that wipes prefs) → 4 editorial steps, "Step 02 / 04" eyebrow,
   skip CTA visible.
3. **Auth invitation** → Apple / Google / Magic Link / Skip.
   Skip → must route to the **Profile wizard** (first-time only),
   not directly home.
4. **Profile wizard** (3 steps) → Nickname → Basics (age + sex
   sheets, "I'll add this later" dismiss visible, "Prefer not to
   say" option present) → Health context (Goals / Conditions /
   Allergies / Medication classes via sheets). Save & continue
   → home.
5. **Home greeting** → "Good morning, {nickname}" if set, or just
   "Good morning" / "Hello there" if skipped. Time-band correctness.
6. **Search v2** → top-level catalog search.
   - Type `omega-3` → on-market results first, off-market
     section labeled "OFF MARKET · OLDER OR DISCONTINUED" with
     calm helper line + dimmed (70% opacity) rows.
   - Header shows split count: `Showing 12 on market · 3 off market`.
   - Toggle list ↔ grid; both modes preserve the partition.
7. **Product Detail v2** → tap any on-market omega-3 from search.
   - All 18 sections render.
   - Trust chips grouped at hero.
   - "Add to Stack" CTA at sticky bottom.
8. **Better Alternatives (v2 ranker)** → from a low-score or
   blocked product, the "Similar higher-quality options" section
   appears with the skeleton placeholder while loading, then 1-3
   cards. Verify **no off-market product** surfaces.
   - **Trip-wire test:** open Vinpocetine (dsld 16012, FDA-banned).
     Section should appear with at least one scored alternative
     (validates the null-score branch from Phase 11.7L.F).
9. **Add to Stack** → confirmation snackbar lands on the parent
   surface (not popped with the screen — validates the
   MedicationEntry snackbar bug fix).
10. **Stack** → newly added item visible. If a medication was
    added (e.g. warfarin), the Stack should show:
    - v2 Stack Safety banner
    - v2 Timing optimization card (cream + accent stripe)
    - v2 Depletion check card (cream + safe/monitor stripe)
11. **MedicationEntry v2** → from Stack → Add medication.
    Search `warfarin` → suggestion rows render.
    No-match → tap "Pick a class instead" → bottom sheet rows
    layout with "I'll add later" dismiss.
12. **Quick Check v2** → from Home or deep link.
    Pick two products that interact (e.g. warfarin + ginkgo).
    Verify result card shows: severity strip + agent A · agent B
    + WHY + WHAT TO DO + evidence overline.
13. **Settings → Edit profile** → routes to v2 ProfileSetup
    **dashboard** (not the wizard — wizard is one-shot).

---

## Known skips (test-only, not blocking ship)

- `test/app_test.dart` — 5 nav-bar tests skipped, pre-existing
  v2-home-shell rendering issue at test time (commit `146626c`).
  Real device works fine. Phase 11.11 rewrite pending.

---

## Known non-blockers

- **pubspec.yaml unnecessary_dev_dependency on crypto** — pre-
  existing analyzer warning, doesn't affect build or runtime.
- **drift double-instantiation warning** at startup (debug only,
  filtered by Sentry beforeSend in 11.7L.D).
- **Sentry environment string** — must be `testflight`, not
  `production`, until the v2 toggles are promoted to default true.
  Set via `SENTRY_ENVIRONMENT=testflight` on the build command;
  `Makefile` includes it in `build-ipa-v2all`.

---

## Trip-wire products (Phase 11.7L.F regression fixtures)

These DSLD IDs are pinned in the Better Alternatives ranker tests.
Visiting any one on device should show **safer** alternatives —
NOT the buggy legacy recommendations:

| dsld_id | Current product | Must NOT appear | Must appear |
|---|---|---|---|
| 315814 | Staminol (GNC, herbal blend) | Basic Prenatal (328830) | Same-audience men's energy product |
| 19170  | Vitamin A 8,000 IU (CVS) | Kids Multi (281264, off-market) | Same-type targeted single-nutrient |
| 1646   | GNC Probiotic Complex 1 | Restore (15581, off-market) | Same-type probiotic w/ ingredient overlap |
| 178559 | Children's Multivitamin Gummies | Basic Prenatal (328830) / A.M. (336315) | Kids multivitamin |
| 16012  | **Vinpocetine** (FDA-banned, no score) | Empty section | At least one scored alternative |

If any expected-NOT product appears, the ranker has regressed —
file a TestFlight blocker and revert the toggle.

---

## Rollback levers (per-surface, no rebuild required for dev runs)

Each toggle defaults `false`. Drop any single flag to fall back
to its legacy widget:

```bash
# Roll back Product Detail only:
make run-v2all  # but drop USE_V2_PRODUCT_DETAIL=true

# Or build a TestFlight IPA with only the surfaces you trust:
flutter build ipa $(DART_DEFINES) \
  --dart-define=USE_V2_PROFILE_SETUP=true \
  --dart-define=USE_V2_SEARCH=true \
  --release  # leaves PD / MedEntry / QuickCheck on legacy
```

For a full rollback to "v2 always-on surfaces only" (splash /
onboarding / auth / home / settings / stack), drop **all five**
`--dart-define` flags:

```bash
make run    # uses no v2 toggles; legacy widgets restored
```

---

## What's NOT in this build (deferred)

- **Scanner v2** (Phase 11.8) — blocked on confirming the PD v2
  TestFlight cycle is clean. The scanner verdict-reveal animation
  + camera-permission gates are already v2-style, but the
  scanner-screen chrome is legacy.
- **Search v2 / QuickCheck v2 widget tests** — Phase 11.10.5
  follow-up (the existing tests target the legacy screens; new
  v2-specific tests will land alongside the default-promotion
  Phase 11.7g.3.f).
- **Phase 9.5 guest scan-limit + stack merge** — separate concern.

---

## Promotion plan (Phase 11.7g.3.f)

After this TestFlight cycle confirms no major regressions on the
walkthrough above:

1. Flip every `defaultValue: false` to `defaultValue: true` in
   `lib/main.dart`:
   - `_useV2ProductDetail`
   - `_useV2ProfileSetup`
   - `_useV2MedicationEntry`
   - `_useV2Search`
   - `_useV2QuickCheck`
2. Update `pubspec.yaml`: `version: 1.0.0+4`.
3. Run `make build-ipa SENTRY_ENVIRONMENT=production` (the
   non-v2all target, since defaults now equal v2).
4. Phase 11.11 cleanup pass — delete legacy widget files +
   `@Deprecated` markers + the `useV2*` toggle plumbing.

If any v2 surface fails the walkthrough, **do not** flip its
default in step 1 — leave the toggle off, file a follow-up phase
ticket, and iterate.

---

## Sentry expectations

- Environment tag: `testflight`
- Dashboard should stay clean — the dev-environment noise filter
  (Phase 11.7L.D, commit `d862c57`) suppresses framework debug
  asserts that historically polluted the live tab.
- Watch for new `BetterAlternatives` issues — the ranker rewrote
  the comparison logic and any unexpected null-deref would surface
  here first.
- Watch for `PageController` issues from the new profile wizard —
  the Sentry fix from 11.7L.D handles the OnboardingV2 case, but
  the wizard has its own controller lifecycle.
