# Flutter Score Explanation UI Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every v4 score pillar understandable in place, remove dead navigation, clarify ingredient form/dose chips, and render label-native identity without inventing scoring rationale.

**Architecture:** Extend the existing shared v4 parser with optional pipeline facts and a shared presentation status. Keep all explanation content data-driven. Convert the score card into a controlled single-open accordion, then update Product Detail wiring and ingredient adapters to consume the label-fidelity contract with a safe legacy fallback.

**Tech Stack:** Flutter/Dart, Material widgets, Riverpod/GoRouter unchanged, `flutter_test`.

**Repository target:** Execute every path and command in this plan from the isolated Flutter worktree at `/Users/seancheick/.config/superpowers/worktrees/pharmaguide-ai/score-explanation-identity`.

---

### Task 1: Shared pillar status and explanation parsing

**Files:**
- Modify: `lib/core/scoring/v4_pillars.dart`
- Modify: `test/core/scoring/v4_pillars_test.dart`

- [ ] **Step 1: Write failing parser/presentation tests**

Cover schema-version-1 fact parsing, malformed-fact omission, old reason-only blobs, exact display order, and status boundaries: 85% Strong, 60% Mixed, below 60% Limited.

- [ ] **Step 2: Verify RED**

Run: `flutter test test/core/scoring/v4_pillars_test.dart`

Expected: FAIL on missing facts/status API.

- [ ] **Step 3: Implement the shared model**

Add immutable `V4PillarFact`, `V4PillarStatus`, `statusForPillar(score,max)`, status label, and the single keyed destination-label map:

```dart
const kV4PillarActionLabels = {
  'evidence': 'View clinical evidence',
  'verification': 'View certifications',
  'transparency': 'View label details',
};
```

Parse only `explanation.schema_version == 1`; preserve pipeline strings verbatim and omit malformed facts. Old blobs remain valid with an empty fact list.

- [ ] **Step 4: Verify GREEN and analyze touched files**

```bash
flutter test test/core/scoring/v4_pillars_test.dart
flutter analyze lib/core/scoring/v4_pillars.dart test/core/scoring/v4_pillars_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/core/scoring/v4_pillars.dart test/core/scoring/v4_pillars_test.dart
git commit -m "feat(score): parse pillar facts and status"
```

### Task 2: Controlled score explanation card

**Files:**
- Modify: `lib/core/components/pg_score_breakdown_card.dart`
- Modify: `test/features/product_detail/score_breakdown_card_test.dart`

- [ ] **Step 1: Write failing widget tests**

Assert all rows start collapsed, opening one closes the prior row, reason then facts then named action render in order, status text accompanies color, Formulation 13.9/20 is Mixed, generic `See details` and app-generated `Biggest opportunity` are absent, and the header has a tappable `How scoring works` action.

Also assert the card has no locally synthesized verification/manufacturer badges; explanatory content is reason plus pipeline facts only.

- [ ] **Step 2: Verify RED**

Run: `flutter test test/features/product_detail/score_breakdown_card_test.dart`

- [ ] **Step 3: Implement the controlled accordion**

Move expansion state to `PGScoreBreakdownCard`; rows receive `isExpanded` and `onToggle`. Extend `PGPillar` with facts and optional `actionLabel`/`onAction`, and use `statusForPillar` for label/tone. Remove `_biggestOpportunity`, `PGPillarBadge`, badge rendering, generic action copy, and per-row independent state. Keep dimensions stable and semantics accessible.

- [ ] **Step 4: Verify GREEN**

```bash
flutter test test/features/product_detail/score_breakdown_card_test.dart
flutter analyze lib/core/components/pg_score_breakdown_card.dart test/features/product_detail/score_breakdown_card_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/core/components/pg_score_breakdown_card.dart test/features/product_detail/score_breakdown_card_test.dart
git commit -m "feat(score): explain pillars in a single-open card"
```

### Task 3: Score section data and action mapping

**Files:**
- Modify: `lib/features/product_detail/v2/sections/score_breakdown_section.dart`
- Modify: `test/features/product_detail/v2/sections/score_breakdown_section_v4_test.dart`

- [ ] **Step 1: Write failing adapter tests**

Assert facts flow from `quality_pillars_v4` to the card verbatim; only evidence, verification, and transparency can receive named actions; an absent target renders no action; Formulation/Dose/Safety never get an action; `How scoring works` is inside the card; and third-party/manufacturer booleans do not create explanatory badges.

- [ ] **Step 2: Verify RED**

Run: `flutter test test/features/product_detail/v2/sections/score_breakdown_section_v4_test.dart`

- [ ] **Step 3: Update the adapter**

Replace `onPillarTap` with destination callbacks keyed by the shared map. Pass reason/facts/action to `PGPillar`. Delete the `hasThirdPartyTesting` / `isTrustedManufacturer` badge synthesis, but temporarily retain those named parameters as ignored compatibility inputs so the existing connected-page caller still compiles until Task 4. Those signals remain available in their dedicated certification/product surfaces. Remove the separate `_HowScoringWorksLink` below the card and call the existing trust-receipts sheet from the card header callback.

- [ ] **Step 4: Verify GREEN**

```bash
flutter test test/features/product_detail/v2/sections/score_breakdown_section_v4_test.dart
flutter analyze lib/features/product_detail/v2/sections/score_breakdown_section.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/product_detail/v2/sections/score_breakdown_section.dart test/features/product_detail/v2/sections/score_breakdown_section_v4_test.dart
git commit -m "fix(score): replace dead pillar links with named actions"
```

### Task 4: Product Detail wiring and duplicate trust removal

**Files:**
- Modify: `lib/features/product_detail/v2/sections/score_breakdown_section.dart`
- Modify: `lib/features/product_detail/v2/product_detail_v2_connected.dart`
- Modify: `test/features/product_detail/v2/product_detail_v2_connected_test.dart`

- [ ] **Step 1: Add failing connected-page tests**

Assert Formulation and Dose cannot scroll to Ingredients, the three eligible destinations still scroll only when present, and the bottom `How we score` row is gone while the card's `How scoring works` remains.

- [ ] **Step 2: Verify RED**

Run: `flutter test test/features/product_detail/v2/product_detail_v2_connected_test.dart`

- [ ] **Step 3: Remove dead callbacks and duplicate row**

Build destination callbacks only for Evidence, Verification, and conditional Transparency. Remove the now-unused compatibility parameters from `buildScoreBreakdownSection` and from this caller in the same commit. Remove `_WhyTrustThisRow` and its page-bottom insertion. Do not change timing, ingredient, or trust-sheet behavior elsewhere.

- [ ] **Step 4: Verify GREEN**

```bash
flutter test test/features/product_detail/v2/product_detail_v2_connected_test.dart
flutter analyze lib/features/product_detail/v2/sections/score_breakdown_section.dart lib/features/product_detail/v2/product_detail_v2_connected.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/product_detail/v2/sections/score_breakdown_section.dart lib/features/product_detail/v2/product_detail_v2_connected.dart test/features/product_detail/v2/product_detail_v2_connected_test.dart
git commit -m "fix(product): remove dead score navigation"
```

### Task 5: Explicit form chips and label-first ingredient adapter

**Files:**
- Modify: `lib/features/product_detail/widgets/ingredient_explain_model.dart`
- Modify: `lib/features/product_detail/v2/sections/ingredients_helpers.dart`
- Modify: `test/features/product_detail/v2/sections/ingredients_helpers_test.dart`

- [ ] **Step 1: Write failing helper tests**

Assert:

- form chip labels are `Excellent form`, `Good form`, `Fair form`, `Poor form`;
- `label_display_name` and `label_display_form` win over canonical/legacy fields without lowercasing;
- legacy blobs still use existing `display_label` behavior.

- [ ] **Step 2: Verify RED**

Run: `flutter test test/features/product_detail/v2/sections/ingredients_helpers_test.dart test/features/product_detail/widgets/ingredient_explain_model_test.dart`

- [ ] **Step 3: Update shared labels and map adapter**

Change only the shared `formChipLabel` helper for chip copy. In `activeFromMap`, prefer label-fidelity fields and preserve form casing. Do not infer identity from canonical fields. Identity-review suppression is added atomically with its typed model in the next task so this commit remains compilable.

- [ ] **Step 4: Verify GREEN**

```bash
flutter test test/features/product_detail/v2/sections/ingredients_helpers_test.dart test/features/product_detail/widgets/ingredient_explain_model_test.dart
flutter analyze lib/features/product_detail/widgets/ingredient_explain_model.dart lib/features/product_detail/v2/sections/ingredients_helpers.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/product_detail/widgets/ingredient_explain_model.dart lib/features/product_detail/v2/sections/ingredients_helpers.dart test/features/product_detail/v2/sections/ingredients_helpers_test.dart
git commit -m "fix(ingredients): render label-first form and dose states"
```

### Task 6: Typed identity-review suppression

**Files:**
- Modify: `lib/core/components/pg_ingredient_data.dart`
- Modify: `lib/features/product_detail/v2/sections/ingredients_helpers.dart`
- Modify: `test/features/product_detail/v2/sections/ingredients_helpers_test.dart`

- [ ] **Step 1: Write failing adapter tests**

Assert conflict/missing-display rows use literal source label text, set `identityNeedsReview`, and return unknown form quality, no dose callout, and no safety claim.

- [ ] **Step 2: Verify RED**

Run: `flutter test test/features/product_detail/v2/sections/ingredients_helpers_test.dart`

- [ ] **Step 3: Implement the typed fallback**

Add `identityNeedsReview` to `PGActiveIngredient`. In `activeFromMap`, detect `identity_conflict` and `missing_display_label`, prefer the literal source name, and suppress form quality, dose callout, and safety claims.

- [ ] **Step 4: Verify GREEN**

```bash
flutter test test/features/product_detail/v2/sections/ingredients_helpers_test.dart
flutter analyze lib/core/components/pg_ingredient_data.dart lib/features/product_detail/v2/sections/ingredients_helpers.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/core/components/pg_ingredient_data.dart lib/features/product_detail/v2/sections/ingredients_helpers.dart test/features/product_detail/v2/sections/ingredients_helpers_test.dart
git commit -m "fix(ingredients): suppress unresolved identity claims"
```

### Task 7: Ingredient tile identity fallback

**Files:**
- Modify: `lib/core/components/pg_ingredient_tile.dart`
- Modify: `test/core/components/pg_ingredient_tile_test.dart`

- [ ] **Step 1: Write failing tile tests**

Assert form label casing is preserved, explicit form chips render the `form` suffix, and an integrity-review row shows `Identity needs review` while hiding form/dose/safety chips.

- [ ] **Step 2: Verify RED**

Run: `flutter test test/core/components/pg_ingredient_tile_test.dart`

- [ ] **Step 3: Render the fallback**

Render one calm neutral diagnostic chip/line for `identityNeedsReview`. When true, do not render form quality, dose callout, or safety claims. Remove unconditional `.toLowerCase()` from the label-native form helper.

- [ ] **Step 4: Verify GREEN**

```bash
flutter test test/core/components/pg_ingredient_tile_test.dart
flutter analyze lib/core/components/pg_ingredient_tile.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/core/components/pg_ingredient_tile.dart test/core/components/pg_ingredient_tile_test.dart
git commit -m "fix(ingredients): hedge unresolved label identity"
```

### Task 8: Compare parity and Flutter closeout

**Files:**
- Modify: `lib/core/components/pg_compare_pillar_row.dart`
- Modify: `test/features/compare/compare_screen_test.dart`
- Modify: `SPRINT_TRACKER.md`

- [ ] **Step 1: Add/adjust Compare regression coverage**

Assert Compare uses the same Strong/Mixed/Limited thresholds and displays the status label beside each score. Update `PGComparePillarRow` to consume `statusForPillar`; do not duplicate thresholds.

- [ ] **Step 2: Run all focused tests**

```bash
flutter test test/core/scoring/v4_pillars_test.dart test/features/product_detail/score_breakdown_card_test.dart test/features/product_detail/v2/sections/score_breakdown_section_v4_test.dart test/features/product_detail/v2/product_detail_v2_connected_test.dart test/features/product_detail/widgets/ingredient_explain_model_test.dart test/features/product_detail/v2/sections/ingredients_helpers_test.dart test/core/components/pg_ingredient_tile_test.dart test/features/compare/compare_screen_test.dart
```

- [ ] **Step 3: Run full verification**

```bash
flutter analyze
flutter test
```

Expected: zero analyzer issues and all tests pass.

- [ ] **Step 4: Update the sprint tracker with verified evidence**

Record the completed score-explanation/identity work, exact test count, analyzer result, and the remaining user-run catalog rebuild/simulator check.

- [ ] **Step 5: Commit**

```bash
git add lib/core/components/pg_compare_pillar_row.dart test/features/compare/compare_screen_test.dart SPRINT_TRACKER.md
git commit -m "test(score): verify explanation UI parity"
```
