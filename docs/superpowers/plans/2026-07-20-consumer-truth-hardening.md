# Consumer Truth Hardening Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the package identity, complete label ledger, score confidence, safety alerts, and search variants tell one consistent consumer-facing story across categories.

**Architecture:** Keep `display_ingredients` as the single canonical label ledger and enrich it with general serving variants, exact activity doses, and validated hierarchy. Flutter partitions that one ledger into Nutrition facts, Active ingredients, and Other ingredients; package metadata and score-confidence decisions are shared presentation rules, while warning cards are consolidated by canonical hazard identity and actionability.

**Tech Stack:** Python 3 pipeline + pytest; Flutter/Dart + Drift + Riverpod; Flutter widget/unit tests.

---

### Task 1: Generalize the canonical label ledger

**Files:**
- Modify: `/Users/seancheick/Downloads/dsld_clean/scripts/enhanced_normalizer.py`
- Modify: `/Users/seancheick/Downloads/dsld_clean/scripts/build_final_db.py`
- Test: `/Users/seancheick/Downloads/dsld_clean/scripts/tests/test_build_final_db.py`

- [ ] Add failing canaries for audience-specific alternate servings, enzyme activity units, nutrition units, and orphaned nested rows.
- [ ] Run the focused pytest cases and confirm the failures describe current behavior.
- [ ] Replace probiotic-only duplicate-serving folding with a general source-path/serving-order fold that never sums alternatives and keeps `serving_variants` on one logical label row.
- [ ] Preserve exact label activity values/units and normalize DSLD plural placeholders in `exact_dose_text`.
- [ ] Require nested rows to carry a resolved `parent_label`, or explicitly downgrade them to standalone depth zero when no source parent exists.
- [ ] Run the focused tests and the existing label-ledger/build-final-db suite.

### Task 2: Present the label as one ledger with clear sections

**Files:**
- Modify: `/Users/seancheick/PharmaGuide ai/lib/features/product_detail/v2/sections/ingredients_section.dart`
- Modify: `/Users/seancheick/PharmaGuide ai/lib/core/components/pg_ingredients_card.dart`
- Test: `/Users/seancheick/PharmaGuide ai/test/features/product_detail/v2/ingredients_section_test.dart`

- [ ] Add failing widget tests proving Nutrition facts, Active ingredients, and Other ingredients are separate headings derived from one ledger; structural blend headers are not counted as ingredients; serving variants remain attached to their parent.
- [ ] Run the focused widget tests and confirm failure.
- [ ] Add an optional section label/count contract to `PGActiveIngredientsSection` and partition canonical rows by `display_type`/`source_section` without copying or reinterpreting data.
- [ ] Render structural parents as headers, children indented, and `Form not disclosed` only when a scored active truly lacks a disclosed form.
- [ ] Run focused ingredient and accessibility tests.

### Task 3: Correct package identity and confidence language

**Files:**
- Modify: `/Users/seancheick/PharmaGuide ai/lib/features/product_detail/v2/sections/hero_section.dart`
- Modify: `/Users/seancheick/PharmaGuide ai/lib/core/components/pg_hero_section.dart`
- Test: `/Users/seancheick/PharmaGuide ai/test/features/product_detail/v2/hero_section_test.dart`

- [ ] Add failing tests for 90 softgels / 45 servings, powder net weight, pluralization, and low `v4_confidence` retaining the number but replacing quality adjectives with `Limited assessment`.
- [ ] Run the focused tests and confirm failure.
- [ ] Compose package size from `net_contents_quantity` + `net_contents_unit`, expose servings separately, and keep dosing summary separate.
- [ ] Thread low assessment confidence into the hero score presentation with low-coverage taking precedence.
- [ ] Run hero/component tests.

### Task 4: Use the same confidence and variant identity in search

**Files:**
- Modify: `/Users/seancheick/PharmaGuide ai/lib/features/search/v2/search_v2_screen.dart`
- Modify: `/Users/seancheick/PharmaGuide ai/lib/core/scoring/score_tier.dart`
- Test: `/Users/seancheick/PharmaGuide ai/test/features/search/v2/search_chip_decision_test.dart`

- [ ] Add failing tests for low-confidence score chips and package variants.
- [ ] Run the focused tests and confirm failure.
- [ ] Centralize assessment-confidence normalization beside score tiers and use it in hero/search decisions.
- [ ] Ensure both list and grid results expose package size/form so exact-name variants are distinguishable without changing barcode navigation.
- [ ] Run search, score-tier, and accessibility tests.

### Task 5: Consolidate warnings into actionable incidents

**Files:**
- Modify: `/Users/seancheick/PharmaGuide ai/lib/features/product_detail/v2/warnings_pipeline.dart`
- Test: `/Users/seancheick/PharmaGuide ai/test/features/product_detail/v2/warnings_partition_test.dart`

- [ ] Add failing tests for the same ingredient hazard arriving with different severity/copy/source URLs and for unmatched informational notes.
- [ ] Run the focused tests and confirm failure.
- [ ] Build incident identity from canonical rule/ingredient/profile target rather than display prose; merge sources; retain the strongest valid severity and the most actionable authored copy.
- [ ] Keep only hard global hazards and profile-matched actionable warnings in warning cards/counts; do not promote neutral “good to know” rows into alerts.
- [ ] Run the full warning/profile-relevance test slice.

### Task 6: Lock release canaries and document the verified contract

**Files:**
- Modify: `/Users/seancheick/Downloads/dsld_clean/scripts/tests/test_build_final_db.py`
- Modify: `/Users/seancheick/PharmaGuide ai/SPRINT_TRACKER.md`
- Modify: `/Users/seancheick/PharmaGuide ai/knowledge/lessons-learned.md`

- [x] Run pipeline focused regression tests and fast contract tests without rebuilding all datasets.
- [x] Run `flutter analyze --fatal-infos`, focused tests, then the full Flutter suite.
- [x] Run whitespace/format checks and review both repository diffs.
- [x] Record exact verification totals and any catalog rebuild still owed.
- [ ] Commit and push both clean repositories to `main` only after every required verification passes.
