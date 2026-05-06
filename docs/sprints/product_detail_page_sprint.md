# Product Detail Page Sprint

Plan source: `~/.claude/plans/also-in-the-plan-zany-zephyr.md` (v4)

## Update rules

- Update this file during implementation.
- Mirror status/sprint changes to `[[lessons-learned]]` when unexpected.
- Do not mark a task `Done` without fresh verification evidence.

## Status legend

- `[x]` = `Done`
- `[-]` = `In Progress` or `Review`
- `[ ]` = `Ready` or `Backlog`

## Tasks

### Flutter — bug fixes
- [x] **T1A** — Sticky CTA never collapses · `pg_stack_action_buttons.dart`
  - DoD: bar visible after `pump(Duration(seconds: 5))` post-add; snackbar still 3s; analyze clean; tests green.
  - Self-eval: every collapse symbol deleted? doc updated? unsafe-product flow unchanged?
  - Verification: 7/7 widget tests green; analyze clean. Converted to ConsumerWidget; deleted `_inStackVisibleWindow`, `_inStackDismissed`, `_lastEntryId`, `_dismissTimer`, `dispose`, `_syncWithEntry`, `AnimatedCrossFade`, `dart:async` import. Doc comment rewritten. Unsafe path unchanged.
- [x] **T1B** — Personalized warnings provider · new provider + screen edits
  - DoD: provider returns mapped warnings on stack mutation without rebuild loops; 3 unit tests pass; manual: add interacting med on Stack tab → return → row appears without restart.
  - Self-eval: autoDispose correct? all `_personalizedWarnings` references gone? `UnimplementedError` and DB exceptions handled?
  - Verification: 4/4 provider tests + 520/520 product_detail suite green. New `personalized_warnings_provider.dart` watches `activeStackProvider`. Removed `_loadPersonalizedInteractions` (~140 LOC), `_extractCanonicalIds`, `_interactionResultToWarning`, `_personalizedWarnings` field, and unused `interaction_result.dart` + `stack_interaction_checker.dart` screen imports. Defensive fallbacks for `UnimplementedError` and `Exception`.

### Flutter — IA consolidation
- [x] **T2A** — ReviewBeforeUseCard (with allergen rows) · new card + `allergen_match.dart`; deletes `alert_summary_card` + `_ConditionAlertBanner`
  - DoD: 12 widget tests pass (incl. T4 gating + 4 allergen cases); allergen matcher tests pass; `AllergenSummaryBanner` suppressed when personalized rows showing; manual walkthrough across monitor/caution/avoid/no-profile/no-match/allergen.
  - Self-eval: exact-ID matching only (no substring)? `_AlertRow` copied not imported? severity tone matches old behavior? `gateInteractionSummary` still wired? presence-type tones correct?
  - Verification: 15 widget tests + 11 matcher tests + 528 product_detail suite all green; `_AlertRow` copied; `gateInteractionSummary` wired; severity tone bumps to danger when allergen `contains` overlays caution warning; AllergenSummaryBanner suppressed when matchedAllergens non-empty. Only the structured `detailBlob['allergens']` path used — no substring fallback.
- [x] **T2B** — `WithYourStackSection` decision (Sean call after T2A walkthrough) — RETIRED 2026-05-05
  - Decision: drop standalone WithYourStackSection AND `_InteractionConditionDetails` ("Relevant to your health"). Both were re-rendering the same profile-matched data ReviewBeforeUseCard already shows.
  - Citations + evidence chips lifted from `WithYourStackSection._ExpandedDetail` into `ReviewBeforeUseCard._AlertRow` so users still have one tap to source URLs. The "✓ No known interaction" positive trust beat dropped per Sean (silence in ReviewBeforeUseCard is sufficient).
  - PopulationsSection content revised: comma-joined "Extra caution for: A, B, C" → bulleted list under "Extra caution if you are…"; "(already covered for X)" parenthetical dropped (mixed drug classes with populations confusingly).
  - Files deleted: `with_your_stack_section.dart` + its test, `_InteractionConditionDetails`/`_ConditionCard` classes.
  - Verification: 539/539 product_detail suite green; analyze clean.
- [x] **T3** — LabelConfidenceCard · new card; deletes 3 banners; lifts product status sheet
  - DoD: 7 widget tests pass; high-confidence chip in hero when applicable; tap on status row opens lifted sheet.
  - Self-eval: orphan imports removed? `_ProductStatusExplanationSheet` lifted before deleting `product_status_chip.dart`? high chip suppressed on blocked products?
  - Verification: 14 widget tests + 524 product_detail suite green. `_ProductStatusExplanationSheet` lifted into `label_confidence_card.dart`. Deleted: `unknown_ingredient_banner.dart`, `blend_warning_banner.dart`, `product_status_chip.dart`, `unmapped_actives_disclosure.dart` + 2 obsolete tests. UnmappedActivesDisclosure unwired from DeepDive. Hero high-confidence chip deferred to T4 (touches `_HeaderSection`).

### Flutter — ingredient row redesign
- [x] **T4A** — Active row (M3) with form helper + Form chip · `_IngredientTile`
  - DoD: row tappable as InkWell; form helper line under name (when form present); Form chip with vocabulary contract (Excellent/Good/Fair/Poor) and Poor=amber; existing tile tests pass; new chip tests cover all 4 bands + null.
  - Verification: 551/551 product_detail tests green. Bio dot removed; whole row InkWell → IngredientExplainSheet; form name as 12sp gray helper line under name (omitted when form null); Form chip uses tokens (severitySafe / scoreGood / severityCaution); Poor downshifted to severityCaution per Sean's rule.
- [x] **T4B** — Dose chip · `_IngredientTile`
  - DoD: High dose / Dose not disclosed render today; Low dose dormant until 7A; tests cover all 4 mappings (Low dose pending).
  - Verification: chips render in `Wrap(spacing: 6, runSpacing: 4)` so they stack on narrow widths. High dose=red (severityAvoid — actual safety); Dose not disclosed=insufficientData gray. Low dose path lit when pipeline ships `below_clinical_dose`.
- [x] **T4C** — IngredientExplainSheet (M3 bottom sheet) + model
  - DoD: pure-function sentence selector unit-tested; sheet uses `showDragHandle: true`, `isScrollControlled: true`, surface tinting; future-data section structurally present; ≤85% screen height max.
  - Verification: 26/26 model unit tests green. `showModalBottomSheet` with `showDragHandle: true`, `isScrollControlled: true`, `useSafeArea: true`, `backgroundColor: surfaceContainerLow`. `DraggableScrollableSheet` 0.4–0.85. Sentence selector picks form-specific copy for glycinate/methylated/MK-7/oxide.
- [x] **T4D** — Inactive role helper · `_InactiveRow`
  - DoD: vocab cached at parent; first role rendered as 12sp gray subtitle; cold-cache and vocab-miss render without helper; tap still opens existing roles sheet.
  - Verification: vocab loaded once via FutureBuilder at IngredientsCard level, snapshot passed down. Cold cache → name-only render (no layout regression). Existing tap modal preserved.
- [x] **T4E** — Section reorder · `DetailSection`
  - DoD: Ingredients above Tradeoffs; ordering test updated; no other layout shifts.
  - Verification: existing `detail_section_order_test.dart` already enforces `inactiveHeaderY < tradeoffsY`. No code change needed; order was already correct.

### Flutter — copy
- [x] **T5** — Rename "Product Analysis" → "Why this scored X" · `score_breakdown_card.dart`
  - DoD: header reads "Why this scored {score}"; test updated.
  - Verification: header interpolates `heroScore` round to int; falls back to "Why this scored" (no number) when score is null; existing pillar bars untouched; tests updated to assert both branches; full product_detail suite (525) green.

### Pipeline
- [x] **T7A** — `below_clinical_dose` flag · `score_supplements.py`
  - DoD: flag in `analyzed_ingredients` rows when `SUB_CLINICAL_DOSE_DETECTED` fires; pipeline test green; sample blob inspected.
  - Verification (2026-05-05): score_supplements._compute_evidence_score now tracks per-canonical sub_clinical_canonicals during the SUB_CLINICAL_DOSE_DETECTED guard and surfaces them at scored.breakdown.C.sub_clinical_canonicals. build_final_db reads this set and marks matching analyzed_ingredients + adequacy_results rows with below_clinical_dose=true|false (always present so Flutter can rely on the field). 3 new tests in test_below_clinical_dose_flag.py + 400 existing tests pass. Pipeline rebuild required for live blobs to carry the flag.
- [x] **T7B-INSPECT** — Pre-OTA spot-check structured allergens (already shipped)
  - DoD: 5–10 real rebuilt blobs inspected covering soy / milk / tree nuts / gluten-free verified / no allergens / may_contain / manufactured_in_facility; cross-walk to Flutter IDs verified; presence-type sort works; no blank `allergen_id`.
  - Verification (2026-05-05): Inspected blobs 1003 (milk contains), 1020 (soy ingredient_list), 12928 (tree_nuts/milk/wheat contains), 14015 (wheat may_contain), 16385 (peanuts/wheat/eggs facility_warning), 1000 (no allergens). Pipeline emits canonical `allergen_id` (ALLERGEN_SOY/MILK/TREE_NUTS/WHEAT/PEANUTS/EGGS — uppercase, stable), `presence_type` ∈ {ingredient_list, contains, may_contain, facility_warning}, `severity_level` ∈ {low, moderate, high}, `display_name`, `evidence`. Flutter matcher (lib/features/product_detail/allergen_match.dart:78,85,92) reads canonical IDs directly, sorts by presence-priority, skips blank IDs. No substring fallback. Cross-walk verified — Flutter ID equals pipeline ID exactly.
- [ ] **T7C** — A1/A2/A5 scoring refactor · `enrich_supplements_v3.py` + `score_supplements.py`
  - DoD: A1 reads `bio_score` only on 0–15 scale, formula `(avg/15)×18`; A2 threshold 12 + reads `bio_score`; A5 +1 for natural-majority; deprecated `score` alias documented; new tests green; shadow-compare run on 1k slice within ±0.5 (or outliers documented).
  - Self-eval: any silent score deflation? `natural` boolean still emitted? alias removal scheduled?
- [ ] **T7D** — Catalog rebuild + bundle ship
  - DoD: new bundle reaches Flutter; simulator smoke green; below-clinical chip lights up where expected.

### Sign-off
- [ ] **SIGNOFF** — High-level architectural eval
  - DoD: criteria below.

## Per-task self-eval discipline

After completing each task, the implementing agent must answer **all four** before flipping to `[x]`:

1. **DoD met?** Tests, manual walkthrough, analyze clean.
2. **Schema mismatches?** Grep blob accessors and column names against the pipeline.
3. **Over-engineering?** Net LOC change reasonable? Any abstraction with one consumer?
4. **Behavior regression?** Run full `test/features/product_detail/` suite; visual diff where applicable.

Any "no" → task moves to `[-]` until resolved.

## Final sign-off

Spawn `system-architect` (or `analyst`) agent with:

> Audit S2.3 implementation under `lib/features/product_detail/` and pipeline changes under `~/Downloads/dsld_clean/scripts/`. Grade against:
> - Code cleanliness & readability
> - Best practices (Dart/Flutter/Riverpod, M3 component usage, pipeline Python)
> - Architectural soundness (no schema mismatches, no orphan widgets, no dead code)
> - Over-engineering (any abstraction with one consumer? premature generalization?)
> - Safety preservation: 3 user-facing safety guarantees in CLAUDE.md hold; no allergen substring fallback shipped; vocabulary contract holds across Form/SafetyTag/ExplainSheet
> - Test coverage adequacy
>
> Produce graded report. Any dimension below "passes bar" → list concrete fixes. Only when every dimension passes do we mark SIGNOFF as `[x]`.

Optional during sign-off:
- `/graphify` — knowledge graph of provider rebuild dependencies for lessons-learned.
- `learn` skill — capture reusable patterns into project memory.
