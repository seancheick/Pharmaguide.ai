# v2 Post-Walkthrough Backlog

**Owner:** Sean
**Created:** 2026-05-16 (after 1.0.0+4 cut)
**Status:** Active triage after TestFlight 1.0.0+4 walkthrough feedback
**Branch:** `design/v2-mobile-polish`

---

## Why this doc

The 1.0.0+4 hotfix (commits `453aab7` + `cee665e`) closed Sean's 11
walkthrough bugs + the Sentry PHARMAGUIDE-W crash. It did NOT cover
the broader v1→v2 coherence gaps Sean wants closed before broader
beta. This doc tracks those items by tier so the next 1-2 builds can
ship them in deliberate batches, not as a single sprint.

**Discipline carries from the hotfix into this work:**
real fixes, not quick patches; toggle-default flips require route
evidence and tests; no legacy deletes or major UX redesigns until a
clean walkthrough on 1.0.0+5.

**2026-05-16 build 1.0.0+4 feedback update:** The build is materially
better, but not coherent enough for another TestFlight upload yet.
Do local simulator / device-simulator verification for the next repair
batches, then cut one larger 1.0.0+5 build only after the route and
state-sync issues below are fixed.

---

## Tier 1 — Walkthrough completeness (next build, 1.0.0+5)

These are the visible gaps where a real-device tester would say "this
isn't doing what it does in v1." They block confidence in the v2
surfaces, not just polish.

### Cluster D (deferred from 1.0.0+4)
- [ ] **Quick Check medication search** — add RxNorm path so a tester
      can find "Lisinopril" alongside supplements. Field-type
      disambiguation needed (supplement vs medication).
      Files: `lib/features/quick_check/quick_check_screen.dart`,
      `lib/features/quick_check/quick_check_logic.dart`,
      `lib/features/quick_check/v2/quick_check_v2_screen.dart`,
      `lib/services/medications/rxnorm_api_service.dart`.

### Route coherence audit (Sean build 1.0.0+4 feedback)
- [ ] **Full v1/v2 route and fallback audit** — identify every path
      that can still unexpectedly land on a legacy surface while the
      tester is in the v2 walkthrough. Include Home CTAs, Stack add,
      Search result tap, Quick Check result tap, Product Result /
      Product Detail, scanner result handoff, and post-add flows.
- [x] **Promote v2 production route defaults** — Search, Product
      Detail, Quick Check, Medication Entry, and Profile Setup now
      default to v2 from source so normal local runs/builds do not
      depend on every command passing the v2 dart-defines. Existing
      per-surface `USE_V2_* = false` dart-defines remain as emergency
      rollback switches.
      ✅ Fixed 2026-05-16: default promotion covered by
      `app_test.dart` route-default guard.
- [x] **Product Result / Product Detail fallback paths** — Product
      Detail v2 is toggle-gated, but Sean still observed v1 rendering
      in some flows. Trace route creation and all `Routes.productDetail`
      call sites; static audit found the route default was legacy unless
      `USE_V2_PRODUCT_DETAIL=true`; now verify scanner/search/quick
      check result handoff on simulator.
      ✅ Fixed/verified 2026-05-16: route defaults now promote Product
      Detail v2, and simulator verified Search → Product Detail,
      Stack row → Product Detail, Quick Check → v2 result flow, and
      manual barcode scan → Product Detail v2.
- [x] **Stack → Add supplement must stay v2** — Sean observed adding
      a supplement from Stack still going to a v1 supplement list.
      Static audit found `Routes.search` was legacy by default; Search
      now defaults to v2, but this still needs simulator verification
      through Stack → Add → Search → Product Detail.
      ✅ Fixed/verified 2026-05-16: Search defaults to v2, Product
      Detail defaults to v2, Add-to-Stack snackbar routes to Stack v2,
      and simulator verified the added product appears in the Stack v2
      list row.
- [x] **Post-add navigation/snackbar flow** — after Add to Stack,
      show a clear path back to Stack. Add a snackbar action such as
      "Go to Stack" or an equivalent v2 affordance so the success
      state is not disconnected from the destination state.
      ✅ Fixed 2026-05-16: `PGStackActionButtons` success snackbar now
      includes "Go to Stack"; regression covered in
      `pg_stack_action_buttons_test.dart`.

### Stack v2 — real safety surfaces (currently legacy embeds)
- [ ] **`_RecallAlertSlot`** — currently passes the raw stack rows;
      verify it actually fires on recalled ingredients with the
      bundled catalog.
- [ ] **`_StackSafetyBannerSlot`** — aggregated safety warnings;
      confirm wiring through `stackSafetyReportProvider`.
- [ ] **`_ProfileNudgeSlot`** — "complete your profile" nudge if
      conditions/goals/allergies are unset.
- [ ] **`NutrientAccumulationPanel`** — production widget exists in
      `lib/features/stack/widgets/nutrient_accumulation_panel.dart`;
      verify it surfaces real UL crossings.
- [ ] **`StackIntelligenceEngine` status tier** — currently the
      summary card uses a hardcoded tier; should consume the real
      `intelligence.status` verdict.
- [x] **Empty-stack stale summary counts** — build 1.0.0+4 showed
      the v2 empty state while the summary still said "3 supplements ·
      1 medication". Remove fixture counts from user-facing empty
      states; fixtures may exist only in dev previews, never after
      `activeStackProvider` has emitted an empty list.
      ✅ Fixed 2026-05-16: Home v2 + Stack v2 now use zero counts
      after `activeStackProvider` resolves empty; regression covered
      in `v2_stack_home_coherence_test.dart`.
- [ ] **Legacy/v2 state-sync pass** — after clearing the stack, adding
      one supplement correctly updated to "1 supplement · 0 meds".
      Audit the transition path so the Stack screen never has two
      visible truths at once: empty list + non-empty summary, or v1
      stack state + v2 stack chrome.

### Home v2 — first-class real data
- [ ] **iOS `CupertinoSliverRefreshControl` + Android
      `RefreshIndicator`** — pull-to-refresh on the home scroll
      (v1 has it, v2 has CupertinoSliverRefreshControl only inside
      Platform.isIOS — needs Android parity).
- [ ] **Real Recent scans** — provider was extended in 1.0.0+4 to
      include upc/imageThumbnailUrl/formFactor. Verify on device
      that real product images actually paint (DSLD thumbnail or
      OFF fallback) before declaring Tier 1 done.
- [ ] **`isFirstLaunchHomeProvider` gate** — first-launch UI subset
      shown to users with empty stack + no recent scans.
- [ ] **`showExpandedSections` conditional** — used by v1 to gate
      heavier sections behind a "see more" interaction.

### Add-supplement flow (Sean's 2026-05-16 13:30 report)
- [x] **"Adding a supplement → v1 supplement list"** — same root
      cause as Cluster D. When `USE_V2_SEARCH` flips post-walkthrough,
      this resolves. **Action: verify in 1.0.0+5 walkthrough that
      Stack → Add → Search now lands in `SearchV2Screen`.**
      ✅ Fixed/verified 2026-05-16: v2 search/detail/stack defaults
      are on, and simulator verified Add-to-Stack → Go to Stack lands
      on `StackV2Screen`.

### Interaction surfaces from build 1.0.0+4 screenshots
- [x] **Add-to-Stack bottom sheet vertical anchoring** — current modal
      opens too high: Cancel / Add actions float far above the bottom
      safe area and feel detached from the nav bar. Rework the sheet
      height / constraints / bottom padding so the action row is
      naturally anchored while still respecting the keyboard and safe
      area.
      ✅ Fixed 2026-05-16: safety sheet is content-sized, no longer
      reserves root nav-bar height inside the modal, and loading text
      no longer overflows; regression covered in
      `pg_stack_action_buttons_test.dart`.
- [x] **Search keyboard gap** — screenshot shows a large white gap
      between the search results list and iOS keyboard. Audit the
      Search v2 scroll/padding/inset behavior and remove any extra
      bottom spacer that is not tied to `viewInsets.bottom`.
      ✅ Fixed 2026-05-16: removed shell nav-bar bottom padding from
      Search v2 and added a keyboard-open inset regression test.

---

## Tier 2 — Visual coherence completion (1.0.0+5 or 1.0.0+6)

Closes the v1/v2 seam that produces the "feels mixed" perception
across surfaces.

- [ ] **`PGFrostedAppBar` v2 tinted variant** — parallel to
      `PGFrostedNavBar`'s `useV2Tones: true`. Stack v2 currently
      builds its own custom AppBar instead of reusing this.
- [ ] **`PGSearchField` v2** — used in `HomeSearchLauncher` (v1
      path); v2 home now uses a custom `_SearchLauncher`. Either
      port the v1 `PGSearchField` to v2 tints, or migrate v1
      callers to use the v2 launcher pattern.
- [ ] **`PGFrostedAppBar` scroll-fade on Stack v2** — v2 stack
      currently uses a flat `V2Colors.bg` AppBar; v1 has the
      cross-fade-on-scroll affordance.
- [ ] **`HomeCitationStrip` → `PGCitationStrip` v2 retint** — real
      catalog count + last-updated label needs v2 typography.
- [ ] **`stack_safety_banner.dart`** — legacy styled; needs v2
      severity-tinted variant matching `PGSeverityBanner` v2 tone.
- [ ] **Recent-scans empty state** — v2 empty state inside Home v2
      (`_RecentScansEmptyState`) — verify it matches the v2
      typography ladder and "Scan your first supplement" pill.

---

## Tier 3 — Real-data integrations (Settings v2)

Settings is currently a v2 chrome over placeholder data. Cleaning
this up is a real engineering pass.

- [x] **Real Supabase `user.email`** — Email tile in Settings v2
      should pull from the authenticated session, not a hardcoded
      placeholder.
      ✅ Fixed 2026-05-16: `SettingsV2Connected` passes the current
      Supabase email into `SettingsV2Screen`; guest Sign in now opens
      the production `/auth` invitation route.
- [ ] **`_PrivacyDashboardSheet`** — v2 sheet showing what data
      lives where (on-device vs Supabase metadata only). Mirror v1
      content + v2 typography.
- [ ] **Real theme picker** — light / dark / system toggle backed by
      `themeProvider` or `SharedPreferences`.
- [ ] **Real notifications toggle** — backed by `flutter_local_notifications`
      permission state and a user opt-in.
- [ ] **Real analytics toggle** — opt-out flag stored locally; gates
      crash-report + telemetry sends.

---

## Tier 4 — Net-new product features

These are NOT bug fixes — they're new product surface. Schedule them
into their own milestones, not as walkthrough work.

- [ ] **Phase 9.5 — Guest scan-limit + stack merge**
      - Guest accounts: cap free scans at N per day; show paywall
        prompt at limit.
      - On sign-in: merge guest stack + scan history into the new
        account's data.
      - Spec needs writing before code; see `knowledge/phase-9.5-guest-merge.md`
        (not yet authored).
- [ ] **Scanner v2 — two-stage flow**
      - Stage 1: scan → quick verdict (safe / caution / avoid + score).
      - Stage 2: tap verdict → Product Detail with hero animation.
      - Hero animation: bottle thumbnail flies from verdict card to
        Product Detail image slot (mirrors the v1
        `flightShuttleBuilder` in home_recent_scans.dart but on the
        verdict → detail handoff).
      - Blocked on Product Detail v2 fully landing (current
        `USE_V2_PRODUCT_DETAIL=false`).

---

## Tier 5 — Polish

Lower-priority surface work. Ship in batches with whichever Tier 1-2
build has room.

- [ ] **Share-clinician-report modal** — current
      `ShareClinicianReportButton` uses the system share sheet.
      A pre-share preview sheet (showing the markdown report
      formatted) would let users vet before sending.
- [ ] **Catalog-unavailable screen v2** — when the OTA catalog isn't
      downloaded yet; v1 has a basic version; v2 should match the
      onboarding tone.
- [ ] **Generic error dialogs** — every "Could not …" snackbar /
      AlertDialog across feature screens needs the v2 tonal
      treatment.
- [ ] **Auth invitation `onPostAuth` polish** — successful sign-in
      currently routes through `_postAuthDestination` to wizard or
      home; the wizard transition could benefit from a brief
      celebration moment matching scan-complete.

---

## Observability follow-up

- [ ] **Verify Sentry `testflight` tag fires cleanly during
      1.0.0+4 walkthrough** — the `SENTRY_ENVIRONMENT` is set to
      `testflight` in `.env`; confirm all events from the new
      build land with the correct tag in the Sentry dashboard.
- [ ] **Sentry breadcrumbs for critical paths**:
      - Add-to-Stack: `Sentry.addBreadcrumb({category: 'stack',
        message: 'add', data: {dsldId, type}})` before
        `StackActions.addProduct` + after success.
      - Scan complete: `Sentry.addBreadcrumb({category: 'scanner',
        message: 'verdict', data: {dsldId, score}})`.
      - Save profile: `Sentry.addBreadcrumb({category: 'profile',
        message: 'save', data: {fields_changed: [...]}})` (no PII —
        field names only).
      - Better Alternatives ranker: log
        `{cur_dsld_id, cur_type, candidate_count, returned_count}`
        so failure modes like KSM-66 are debuggable from a real
        device.

---

## What goes in 1.0.0+5 specifically

After 1.0.0+4 walkthrough passes, the next build should ship:

1. **Tier 1 — Cluster D** (Quick Check medication search)
2. **Tier 1 — Stack v2 safety surfaces** (RecallAlertSlot wiring
   verification, _StackSafetyBannerSlot, NutrientAccumulationPanel)
3. **Tier 1 — Home v2 pull-to-refresh + first-launch gate**
4. **Tier 4 — v2 `onInactiveTap` extraction** (only if 1.0.0+4
   defensive `useRootNavigator` fix did NOT resolve bug 9 on
   real-device retest)
5. **Toggle default flip** (`USE_V2_*` → true) ONLY after the
   above land + a second clean walkthrough

Anything from Tiers 2-5 that fits naturally with the above changes
can ride along; do not pre-load 1.0.0+5 with Tier 5 polish.
