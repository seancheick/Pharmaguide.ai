# Probiotic Label and Research Card Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the ambiguous probiotic checkmark card with an explicit, evidence-scoped, accessible label-and-research explanation.

**Architecture:** Enrichment emits a conservative research presentation contract from the existing clinically reviewed strain database. Flutter parses that contract into a presentational strain model, renders explicit states and source details, and places the card directly after the canonical ingredient ledger. Scoring remains unchanged.

**Tech Stack:** Python 3.13, pytest, Flutter/Dart, Material, flutter_test

---

### Task 1: Pipeline research presentation contract

**Files:**
- Modify: `/Users/seancheick/Downloads/dsld_clean/scripts/enrich_supplements_v3.py`
- Modify: `/Users/seancheick/Downloads/dsld_clean/scripts/tests/test_p05_probiotic_prebiotic_consistency.py`

- [x] Write failing tests for verified exact-strain, pending-review, formula-only, and rejected rows.
- [x] Run the focused tests and confirm contract fields are absent or incorrect.
- [x] Add a pure presentation-contract helper and attach its fields to clinical-strain rows without changing score inputs.
- [x] Run the focused tests and the pipeline fast contract suite.

### Task 2: Flutter model and card behavior

**Files:**
- Modify: `lib/core/components/pg_probiotic_section.dart`
- Modify: `lib/features/product_detail/v2/sections/probiotic_section.dart`
- Modify: `test/features/product_detail/widgets/pipeline_sections/probiotic_detail_section_test.dart`

- [x] Write failing widget tests for explicit statuses, no hollow circles, rejected/pending protection, aggregate CFU copy, explanation sheet, sources, and semantics.
- [x] Run the focused widget tests and confirm the new behavior fails.
- [x] Replace the Boolean research model with explicit scope/status fields and conservative legacy fallbacks.
- [x] Redesign the card hierarchy, feature grouping, detail sheet, source actions, and semantic labels.
- [x] Run focused widget and component tests.

### Task 3: Product-detail placement

**Files:**
- Modify: `lib/features/product_detail/v2/product_detail_v2_connected.dart`
- Modify: `test/features/product_detail/v2/product_detail_v2_connected_test.dart`

- [x] Write a failing ordering test proving the probiotic card follows Ingredients and appears only once.
- [x] Move the card from section 14 to immediately after Ingredients.
- [x] Run the connected-screen tests.

### Task 4: Verification and project record

**Files:**
- Modify: `SPRINT_TRACKER.md`
- Modify: `knowledge/lessons-learned.md`

- [x] Run Python compilation, focused pipeline tests, and the fast suite without rebuilding datasets.
- [x] Run Dart format, Flutter analyzer, focused tests, and full Flutter tests.
- [x] Run both whitespace checks and review both diffs.
- [x] Record exact results and any catalog rebuild still owed.
