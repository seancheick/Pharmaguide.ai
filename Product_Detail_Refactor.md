# Product Detail Refactor — Final Plan

## Context

The product detail page (`lib/features/product_detail/product_detail_screen.dart`, 3499 LOC) has organically grown across Sprints S2.1 + S2.2. Two real safety bugs and an information-architecture problem remain:

1. **Sticky CTA collapses prematurely.** `PGStackActionButtons` cross-fades the bottom bar to height 0 after a 3-second window once an item enters the user's stack (`pg_stack_action_buttons.dart:67-138`). The user loses the In-Stack/Remove control and any later "Add" surface; only the snackbar should be ephemeral, the bar should be permanent.
2. **Personalized warnings don't refresh.** `_loadPersonalizedInteractions()` runs once in `initState` (`product_detail_screen.dart:95, 106-177`) and writes to `_personalizedWarnings` via `setState`. Adding/removing items in the stack from elsewhere doesn't invalidate this list — the page can claim "No interactions" when one exists.
3. **IA is fragmented.** Profile risk surfaces in 3 places (`AlertSummaryCard`, `_ConditionAlertBanner`, `WithYourStackSection`). Label-quality signals scatter across 4 widgets (`UnknownIngredientBanner`, `BlendWarningBanner`, `ProductStatusChip`, `UnmappedActivesDisclosure`).

Sean's review of the dev's draft is largely correct. This plan implements his revised version with concrete file paths, fixes a few mismatches with the actual code, and intentionally avoids a feature-flag scaffold (each phase is its own PR — git is the rollback).

---

## Shape of the change

```
BEFORE                                          AFTER
──────                                          ─────
Hero                                            Hero (+ optional "Label confidence: High" chip)
  ↓                                               ↓
PersonalFitCard                                 PersonalFitCard
  ↓                                               ↓
AlertSummaryCard            ─┐                  ReviewBeforeUseCard          ← Phase 2A
_ConditionAlertBanner       ─┼─ profile risk      • severity tone
ProductStatusChip            │                    • profile-matched details
UnknownIngredientBanner     ─┐                    • no-profile nudge
BlendWarningBanner          ─┼─ label quality      ↓
AllergenSummaryBanner        │                  LabelConfidenceCard          ← Phase 3
UnmappedActivesDisclosure   ─┘                    • coverage / blend / status
  ↓                                               • unmapped actives
ScoreBreakdownCard ("Product Analysis")           ↓
  ↓                                             IngredientsCard              ← swap up
DetailSection {                                   ↓ (active rows: form helper)
  IngredientsCard                                 ↓ (inactive rows: 1-line role)
  TradeoffsSection                                ↓
  WithYourStackSection                          ScoreBreakdownCard           ← rename
  _InteractionConditionDetails                    "Why this scored X"
  SynergyDetailSection                            ↓
  PopulationsSection                            TradeoffsSection
}                                                 ↓
  ↓                                             WithYourStackSection (kept; see Phase 2B)
DeepDiveSection                                   ↓
  ↓                                             SynergyDetailSection / Populations
BetterAlternatives                                ↓
  ↓                                             DeepDiveSection / BetterAlternatives / Footer
TransparencyFooter                              ──────────
                                                Sticky CTA (always visible — bug fixed)


Provider rebuild graph (Phase 1):

  activeStackProvider ──┐
                        ├─→ personalizedInteractionWarningsProvider(dsldId)
  profileProvider ──────┘            (auto-disposes; mirrors fitScoreForProductProvider pattern)
                                     ↓
                                ProductDetailScreen.build()  ← ref.watch(...)
```

---

## Phase 1 — Safety bug fixes (ship first, independent)

### 1A. Sticky CTA never collapses

**File:** `lib/features/product_detail/widgets/pg_stack_action_buttons.dart`

Delete the auto-collapse machinery wholesale. The bar should always render whichever primary the entry state demands; only the snackbar is ephemeral.

- Convert `PGStackActionButtons` from `ConsumerStatefulWidget` → `ConsumerWidget`. (No more setState path.)
- Delete: `_inStackVisibleWindow`, `_inStackDismissed`, `_lastEntryId`, `_dismissTimer`, `dispose`, `_syncWithEntry`, the `AnimatedCrossFade`, the `secondChild` SizedBox.
- `build` returns `_buildBar(context, ref, ref.watch(stackEntryForDsldIdProvider(dsldId)))` directly.
- Snackbar at `_handleAdd` (line 258) and the Remove snackbar (line 286) already auto-dismiss at 3s — leave them as-is. They are the correct ephemeral confirmation.
- Update class doc to remove the 2026-04-30 "auto-collapsing" paragraph and replace with one sentence explaining the bar is persistent.

**Tests:** `test/features/product_detail/widgets/pg_stack_action_buttons_test.dart` — drop any test that asserts the collapse-after-3s behavior; add one test asserting the bar is still rendered after adding to stack (pump `stackEntryForDsldIdProvider` with a non-null entry, expect `find.byType(_InStackPanel)` to remain after `pump(Duration(seconds: 5))`).

### 1B. Personalized warnings refresh on stack change

**New file:** `lib/features/product_detail/providers/personalized_warnings_provider.dart`

Mirror the established `fitScoreForProductProvider` pattern (`lib/features/product_detail/providers/fit_score_provider.dart:108`). One `FutureProvider.family.autoDispose<List<InteractionWarning>, String>` that:

- `ref.watch(activeStackProvider.future)` → triggers rebuild on stack mutations (the provider is invalidated by `StackActions._invalidate` at `active_stack_provider.dart:185-195`).
- `ref.read(coreDatabaseProvider)` and `ref.read(interactionDatabaseProvider)` for the DB handles.
- Body lifts the logic verbatim from `_loadPersonalizedInteractions` (lines 106-177), including the `_extractCanonicalIds` call and `_interactionResultToWarning` mapper. Move both helpers to the provider file (they're static today).
- Catches `UnimplementedError` (test stubs) and `Exception` (DB missing/corrupt) → returns `const []`. Same fail-safe as today.

**File:** `lib/features/product_detail/product_detail_screen.dart`

- Delete: `_personalizedWarnings` field (line 89), the `_loadPersonalizedInteractions()` call from `initState` (line 95), the entire `_loadPersonalizedInteractions` method (lines 106-177), `_extractCanonicalIds` (lines 190-…), `_interactionResultToWarning` (lines 235-246).
- In `build()` near line 323, replace `_personalizedWarnings` with `ref.watch(personalizedInteractionWarningsProvider(widget.dsldId)).valueOrNull ?? const <InteractionWarning>[]`.

**Tests:** new `test/features/product_detail/providers/personalized_warnings_provider_test.dart` — 3 cases: empty stack returns empty, non-empty stack returns mapped warnings, `UnimplementedError` falls back to empty. Use the same overrides pattern as `fit_score_provider_test.dart`.

---

## Phase 2A — ReviewBeforeUseCard

Merge **AlertSummaryCard + `_ConditionAlertBanner`** only. Keep `WithYourStackSection` and `_InteractionConditionDetails` for now (Phase 2B).

**New file:** `lib/features/product_detail/widgets/review_before_use_card.dart`

```dart
class ReviewBeforeUseCard extends ConsumerWidget {
  final List<InteractionWarning> warnings;        // = guardedWarnings
  final String interactionHint;                   // = _product.interactionSummaryHint
  final Map<String, dynamic>? interactionSummary; // = detailBlob['interaction_summary']
  final Map<String, IngredientDose>? ingredientDoses;
  // intentionally NOT: productStatus (label quality, lives in Phase 3)
  // intentionally NOT: allergenSummary (skipped this initiative — see "Deferred" below)
}
```

Behavior (combines today's two surfaces; severity table identical to `_ConditionAlertBanner._toneFor` at line 1238):

| State                                                    | Render                                                                                   |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `guardedWarnings.isEmpty` AND no profile match           | `SizedBox.shrink()`                                                                      |
| Profile empty AND `interactionHint` parses with `hasAny` | Neutral nudge ("Add your conditions and meds to personalize") — copy from line 1167-1173 |
| Profile populated, no overlap                            | `SizedBox.shrink()` (today's behavior at line 1151)                                      |
| Profile match — severity ≥ avoid                         | Expanded by default; tone = danger                                                       |
| Profile match — caution / monitor                        | Collapsed by default; tone follows `computeMatchedHighestSeverity`                       |

Reuse:

- `gateInteractionSummary` (already imported via `condition_gate.dart`)
- `computeMatchedHighestSeverity` (already imported)
- The `_AlertRow` widget from `alert_summary_card.dart:158-249` — copy/move it into the new file. Don't extract a shared lib.
- `PGSeverityBanner` for the title strip (today's banner at line 1209)

Move `_parseHint`, `_listOfStrings`, `_toneFor`, `_titleFor`, `_buildMatchBody`, `_humanizeId`, `_InteractionHint`, `_humanizedConditionLabels` (lines 1213-end of `_ConditionAlertBanner` block) into the new card file. They're private helpers and have one consumer.

**Wire in `product_detail_screen.dart`:**

- Replace the `AlertSummaryCard` sliver (lines 464-475) AND the `_ConditionAlertBanner` sliver (lines 480-494) with a single sliver rendering `ReviewBeforeUseCard`.
- Delete the `_ConditionAlertBanner` class definition (line 1074-end of class).
- Delete `lib/features/product_detail/widgets/alert_summary_card.dart` and its test once the new card test is green.

**Tests:** new `test/features/product_detail/widgets/review_before_use_card_test.dart` — 8 cases: empty (hidden), no-profile nudge, profile-no-match (hidden), monitor-collapsed, caution-collapsed, avoid-expanded, contraindicated-expanded, gating drops a positive condition (Vit D × Diabetes case from T4 follow-up).

---

## Phase 2B — Decide `WithYourStackSection` fate (after Phase 2A walkthrough)

Sean's call once 2A is live: keep, fold, or move below. **No code changes in this phase by default** — capture the decision, log a follow-up task. The current call site (`product_detail_screen.dart:2346-2350`) is fine in place; folding would risk losing the per-condition / per-drug-class confirmation rows ("✓ Hypertension — No known interaction") that are the deeper trust beat.

If Sean greenlights folding into ReviewBeforeUseCard, the implementation is mechanical: pass `userConditions` + `userDrugClasses`, render the row list inside the expanded body. Out of scope here.

---

## Phase 3 — LabelConfidenceCard

**New file:** `lib/features/product_detail/widgets/label_confidence_card.dart`

```dart
class LabelConfidenceCard extends StatelessWidget {
  final double mappedCoverage;                      // _product.mappedCoverage
  final bool hasProprietaryBlends;                  // detailBlob.proprietary_blend_detail.has_proprietary_blends
  final Map<String, dynamic>? productStatus;        // detailBlob.product_status
  final Map<String, dynamic>? unmappedActives;      // detailBlob.unmapped_actives
  final bool isNotScored;
}
```

Single neutral/amber card (never red — recalled/banned products go through `BlockedBanner` on the hero, not this card). Behavior matrix:

| Coverage                                                       | Render                                                                                                           |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `>= 0.5` AND no blend AND no status AND no unmapped AND scored | `SizedBox.shrink()`                                                                                              |
| `>= 0.5` AND none of the above                                 | `SizedBox.shrink()` and surface a tiny "Label confidence: High" chip near the hero score (see hero change below) |
| `< 0.5` OR any signal present                                  | Render the card                                                                                                  |

Card content (one row per signal, only when applicable):

- Coverage: copy from `UnknownIngredientBanner` (lines 21-25), tier color via existing logic.
- Proprietary blend: copy from `BlendWarningBanner` (line 28-30).
- Product status: row + tap → existing `_ProductStatusExplanationSheet` (already in `product_status_chip.dart:130`). Reuse the sheet; don't rebuild the bottom-sheet body.
- Unmapped actives: same `UnmappedActivesDisclosure` body folded in as a row.
- Not-scored: one-line "Not enough verified data to score." (already rendered today on the hero ScoreLine; keep that hero copy AND show it here when other signals fire).

**Hero high-confidence chip** (in `_HeaderSection` inside `product_detail_screen.dart`):

- Add an optional `confidenceLabel` param to `_HeaderSection`. When passed, render a tiny chip below the chip row, above `ScoreLine`. Pass `'Label confidence: High'` only when `mappedCoverage >= 0.5` AND no other label signals fire.
- One line of code in `build()` deciding whether to show it.

**Wire in `product_detail_screen.dart`:**

- Replace these slivers with one `LabelConfidenceCard` sliver, placed where `ProductStatusChip` is today (between Review-Before-Use and ScoreBreakdownCard):
  - `ProductStatusChip` sliver (lines 501-507)
  - `UnknownIngredientBanner` sliver (lines 513-523)
  - `BlendWarningBanner` sliver (lines 524-535)
  - `UnmappedActivesDisclosure` call inside DeepDive — leave its DeepDive call site if it appears there too; double-check via grep, this initiative only moves the duplicate.
- Delete the standalone widget files once tests are green: `unknown_ingredient_banner.dart`, `blend_warning_banner.dart`, `product_status_chip.dart` (keep `_ProductStatusExplanationSheet` by lifting it into `label_confidence_card.dart`).

**Tests:** new `test/features/product_detail/widgets/label_confidence_card_test.dart` — 6 cases: empty (hidden), low coverage only, blend only, status only, unmapped only, all four signals together.

**Allergens — explicitly deferred.** `_product.allergenSummary` is a single label string today (`product_detail_screen.dart:618-631`); there is no user-side allergen profile field. Splitting into "personal vs generic" requires a profile schema change. Out of scope for this initiative — leave `AllergenSummaryBanner` exactly where it is. Add backlog item `B7: user allergen profile + personalized allergen surface`.

---

## Phase 4 — Ingredient microcopy

### 4A. Active ingredient row — bioavailable form helper

**File:** `lib/features/product_detail/product_detail_screen.dart` — `_IngredientTile.build()` at line 2783-2832.

Add a one-line helper after the `_SafetyTag` / form chip wrap, only when both:

1. `bioScore != null && (bioScore as num) >= 12` (the same threshold `_bioColor` uses for the green dot)
2. `form.isNotEmpty`

Helper text uses **safer wording per Sean's note**: `'Bioavailable form'` (not "highly bioavailable"). One Text widget, `bodySmall`, `onSurfaceVariant`, no extra padding beyond what's already there. Trust the bioScore; don't re-invoke a vocab.

For `bioScore < 4` AND `form.isNotEmpty`, show `'Lower-absorption form'` in the same slot — symmetric, equally honest.

Mid-range (4 ≤ bioScore < 12): no helper. Don't make claims we can't back.

### 4B. Inactive ingredient row — one-line role helper

**File:** `lib/features/product_detail/widgets/ingredients_card.dart` — `_InactiveRow` at line 212-269.

Pull the **first** functional role from `ingredient['functional_roles']`, look it up against the existing `loadFunctionalRolesVocab()` cache (`functional_roles_vocab.dart:115`), and render `role.name` as a tiny one-line subtitle below the ingredient name.

- Cache the vocab in a `FutureBuilder` at the `IngredientsCard` level (one builder for the whole list — don't FutureBuild per row). On first frame the cache is cold but the assets load is sync after that — pass a snapshot `Map<String, FunctionalRole>?` down to `_InactiveRow` and let null mean "no helper line yet, render plain."
- When no role / vocab miss / cache cold → no helper line. Row falls back to today's name-only render. No layout regression.
- Tap behavior unchanged: still opens `_FunctionalRolesSheet`.

This delivers the "Filler / Emulsifier / Capsule shell" inline answer Sean wants without a new asset — the vocab is already shipped.

### 4C. Section order swap

Inside `DetailSection` (`product_detail_screen.dart` around line 2200-2350), move the `IngredientsCard` block above the `TradeoffsSection` block. Ingredients first, then "What's good / What to consider", per Sean's recommended order.

Pin-the-order test (`test/features/product_detail/widgets/detail_section_order_test.dart`) — update the expected y-ordering.

**Tests:**

- `_IngredientTile` widget tests: bioScore=14 + form="bisglycinate" → "Bioavailable form" present; bioScore=2 + form="oxide" → "Lower-absorption form" present; bioScore=8 → no helper.
- `_InactiveRow` widget tests: with vocab snapshot, role.name visible as subtitle; without snapshot, name-only render.

---

## Phase 5 — Rename "Product Analysis" → "Why this scored X"

**File:** `lib/features/product_detail/widgets/score_breakdown_card.dart`

Header copy change. Currently set to `'Product Analysis'` (T14, 2026-04-29 PM). Change to `'Why this scored X'` where `X` = the displayed score (the card already receives `heroScore` per `product_detail_screen.dart:563`). Use string interpolation against the same value.

The four pillar bars + micro-explanations stay. No layout change.

**Tests:** update `test/features/product_detail/score_breakdown_card_test.dart` header-copy assertions.

---

## Phase 6 — Page-level provider seed (no full refactor)

The personalized-warnings provider from Phase 1B IS the seed. Beyond that, no `ProductDetailUiState` refactor in this initiative — Sean's call. The `_product` and `_personalizedWarnings` migration is the foothold; future sprints can fold `_loadProduct`, `detailBlob`, `fitScore`, and the gated-warnings list into a single screen-state provider when there's appetite.

Document this explicitly in the PR description: "Phase 6 deferred. Foothold landed in Phase 1B."

---

## Files modified (summary)

**New:**

- `lib/features/product_detail/providers/personalized_warnings_provider.dart`
- `lib/features/product_detail/widgets/review_before_use_card.dart`
- `lib/features/product_detail/widgets/label_confidence_card.dart`

**Modified:**

- `lib/features/product_detail/widgets/pg_stack_action_buttons.dart` (Phase 1A — net delete ~80 LOC)
- `lib/features/product_detail/product_detail_screen.dart` (all phases — net delete is the goal)
- `lib/features/product_detail/widgets/ingredients_card.dart` (Phase 4B)
- `lib/features/product_detail/widgets/score_breakdown_card.dart` (Phase 5)
- `test/features/product_detail/widgets/detail_section_order_test.dart` (Phase 4C)

**Deleted (after their replacements pass tests):**

- `lib/features/product_detail/widgets/alert_summary_card.dart` + test
- `lib/features/product_detail/widgets/unknown_ingredient_banner.dart`
- `lib/features/product_detail/widgets/blend_warning_banner.dart`
- `lib/features/product_detail/widgets/product_status_chip.dart` (lift `_ProductStatusExplanationSheet` first)

**Untouched on purpose:**

- `with_your_stack_section.dart` (Phase 2B is a future call)
- `tradeoffs_section.dart` (already cleaned in T15 — only an ordering swap, no edits)
- `personal_fit_card.dart` (no scope here)
- `pipeline_sections/allergen_summary_banner.dart` (deferred per Phase 3)

---

## Verification

Each phase ships its own PR. Per-phase gate:

1. `flutter analyze --fatal-infos` → **No issues found**
2. `flutter test test/features/product_detail/` → all green; count steady or up
3. `flutter test test/services/warnings/` → all green (gating logic untouched, but Phase 2A moves callers — confirm)
4. `make check` → green
5. **Manual walkthrough on simulator** for the affected matrix:
   - Phase 1A: add product to stack → CTA stays visible as "In Stack | Remove" indefinitely; snackbar disappears at 3s.
   - Phase 1B: open product page → add an interacting medication on the Stack tab → return to product page → personalized warning appears without restart.
   - Phase 2A: Vit D × Diabetes profile → no false-positive in the new card (T4 gating preserved); avoid-tier warning auto-expands; monitor-tier collapses.
   - Phase 3: low-coverage product → card renders coverage row; high-coverage product → card hidden, hero shows "Label confidence: High" chip.
   - Phase 4A: Magnesium Bisglycinate (bioScore high) → "Bioavailable form" inline; magnesium oxide (bioScore low) → "Lower-absorption form".
   - Phase 4B: tap an inactive ingredient → row already shows "Filler" / "Emulsifier" subtitle from vocab; tap opens existing sheet.

**Schema-mismatch checklist** (run before each PR):

- All blob reads use the same accessors as today (`detailBlob['product_status']`, `detailBlob['interaction_summary']`, `detailBlob['proprietary_blend_detail']`, `detailBlob['unmapped_actives']`). Grep before commit.
- No new fields read from `ProductsCoreData` beyond what's already there.
- No new asset files; reuse `functional_roles_vocab.json`.

**Rollback:** each phase = one PR. Revert that PR if a regression surfaces. No feature-flag plumbing — keeps the diff small and avoids `useReviewBeforeUseCard = true` dead code drifting in the tree.

---

## What I'm intentionally NOT doing (and why)

- **No feature flag scaffold** — the dev's draft suggested `useReviewBeforeUseCard = true` constants. With per-phase PRs and 1241 existing tests, git is the rollback path. Adding flags adds dead code that always ships.
- **No full `ProductDetailUiState` refactor** — Sean explicitly deferred it; Phase 1B's provider is the seed.
- **No allergen personalization** — would require a `profile.allergens` field that doesn't exist. Backlog `B7`.
- **No "Quality / Strong / Moderate / Limited" chip per active ingredient** — already in the existing backlog as `B2`.
- **No ingredient deep-dive sheet** — already `B8`.
- **No copy changes inside `_FunctionalRolesSheet`** — it's clinician-locked per the file's class doc.
- **No removal of the `AllergenSummaryBanner` call site** — it's harmless where it is; folding it would force the schema change above.
