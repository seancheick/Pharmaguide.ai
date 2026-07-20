# Label Truth and Trust Architecture Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the product detail screen faithfully reproduce the source label, keep scoring as a clearly separate analysis layer, expose product/version provenance, and create a privacy-safe correction and operations loop.

**Architecture:** The Python pipeline emits one ordered `display_ingredients` label ledger plus separate scored ingredients. Flutter builds one immutable presentation model from the ledger and reuses it for rows and sheets. Product match/version metadata remains informational and never changes FitScore. P0 release gates fail closed on disputed identities, false form claims, and unsupported completeness claims; P1 makes provenance inspectable; P2 adds authenticated reporting and aggregate operations signals without health data.

**Tech Stack:** Flutter/Dart, Riverpod, Drift, GoRouter, Supabase Auth/Postgres/Storage, Python/pytest pipeline.

**Repository roots:**

- Flutter: `/Users/seancheick/.config/superpowers/worktrees/PharmaGuide-ai/label-trust-p0-p2`
- Pipeline: `/Users/seancheick/.config/superpowers/worktrees/dsld_clean/label-trust-p0-p2`

---

## P0 — Stop Trust Regressions

### Task 1: Preserve a complete canonical label ledger

**Files:**

- Modify: pipeline `scripts/enhanced_normalizer.py`
- Modify: pipeline `scripts/build_final_db.py`
- Test: pipeline `scripts/tests/test_build_final_db.py`

- [x] Add failing canaries for omega hierarchy, one-row folate DFE/folic-acid equivalence, label order, lineage, exact dose text, and non-scoring context rows.
- [x] Run `scripts/test.sh fast scripts/tests/test_build_final_db.py` and confirm the new assertions fail for missing/flattened rows.
- [x] Make `display_ingredients` preserve every supported source-label row with `display_disposition`, hierarchy, scoring participation, form states, identity state, and allowed omission metadata.
- [x] Keep label-context rows out of all score/dose/safety inputs.
- [x] Re-run the focused file and confirm green.

### Task 2: Make identity and form integrity fail closed

**Files:**

- Modify: pipeline `scripts/enrichment_contract_validator.py`
- Modify: pipeline `scripts/audit_identity_integrity.py`
- Test: pipeline `scripts/tests/test_contract_validation.py`

- [x] Add failing tests for disclosed form incorrectly marked `not_disclosed`, score-included identity conflicts, missing display identity, unsupported completeness claims, and the closed omission-reason enum.
- [x] Add a failing release-audit case proving a `needs_review` row cannot ship with dose, form-quality, or safety claims.
- [x] Implement validation and publication-blocking audit results without inventing or repairing clinical identity in the validator.
- [x] Verify `scripts/test.sh fast scripts/tests/test_contract_validation.py`.

### Task 2B: Emit the mandatory ledger reconciliation audit

**Files:**

- Modify: pipeline `scripts/enhanced_normalizer.py`
- Modify: pipeline `scripts/build_final_db.py`
- Modify/Test: pipeline `scripts/tests/test_build_final_db.py`

- [x] Add failing tests for `label_source_rows` across active, Other Ingredients,
  decorative, blank, and nested source occurrences; every stable source path
  must resolve to display or omission evidence.
- [x] Add failing tests for deterministic `label_ledger_audit` counts and the
  first-release supported archetypes, plus unavailable completeness for an
  unsupported structure.
- [x] Emit both contracts without feeding them into scoring, dose, safety, or
  warning calculations.
- [x] Verify `scripts/test.sh fast scripts/tests/test_build_final_db.py`, then
  run the Task 2 contract/audit suites together.

### Task 3: Correct formulation rationale without changing the score core

**Files:**

- Modify: pipeline `scripts/scoring_v4/quality_score.py`
- Test: pipeline `scripts/tests/test_v4_quality_score.py`

- [x] Add failing fish-oil tests proving no molecular form claim is inferred from parent ingredient identity and that rationale names disclosed-form coverage and EPA+DHA concentration.
- [x] Implement explanation-only signal reconciliation while preserving the numeric pillar calculation.
- [x] Verify `scripts/test.sh fast scripts/tests/test_v4_quality_score.py`.

### Task 4: Reconcile evidence scope and unit variants

**Files:**

- Modify: pipeline `scripts/scoring_v4/modules/generic_evidence.py`
- Test: pipeline `scripts/tests/test_v4_generic_evidence_p133.py`

- [x] Add a failing canary that a Vitamin D IU label resolves the same ingredient evidence as its equivalent supported quantity form.
- [x] Normalize evidence matching inputs only; do not fabricate product-level studies.
- [x] Verify `scripts/test.sh fast scripts/tests/test_v4_generic_evidence_p133.py`.

### Task 5: Introduce one Flutter ingredient presentation contract

**Files:**

- Add: Flutter `lib/features/product_detail/label_ingredient_presenter.dart`
- Modify: Flutter `lib/core/components/pg_ingredient_data.dart`
- Add: Flutter `test/features/product_detail/label_ingredient_presenter_test.dart`

- [x] Write failing model tests for assessed, `not_disclosed`, `listed_not_assessed`, `not_applicable`, and `needs_review`; label-first identity; exact dose; hierarchy; scoring context; and identity-claim suppression.
- [x] Implement a pure presenter with no Widget/context dependencies.
- [x] Verify the focused test and `flutter analyze`.

### Task 6: Make ingredient rows and explanation sheets agree

**Files:**

- Modify: Flutter `lib/features/product_detail/v2/sections/ingredients_helpers.dart`
- Modify: Flutter `lib/features/product_detail/widgets/ingredient_explain_model.dart`
- Modify/Test: Flutter `test/features/product_detail/widgets/ingredient_explain_model_test.dart`

- [x] Add failing row/sheet parity tests, including fish oil with an undisclosed form and disclosed-but-unmapped form text.
- [x] Route both adapters through the shared presenter; never derive a quality badge from `bio_score` unless the form state is `assessed`.
- [x] Verify the focused test and `flutter analyze`.

### Task 7: Render the label ledger in source order

**Files:**

- Modify: Flutter `lib/features/product_detail/v2/product_detail_v2_connected.dart`
- Modify: Flutter `lib/features/product_detail/v2/sections/ingredients_section.dart`
- Modify/Test: Flutter `test/features/product_detail/v2/product_detail_v2_connected_test.dart`

- [x] Add failing widget tests proving `display_ingredients` wins, source order and nesting survive, and the legacy scoring list is an explicit fallback only.
- [x] Remove analysis sorting/regrouping from the label path while preserving legacy behavior for stale blobs.
- [x] Verify the focused test and `flutter analyze`.

### Task 8: Make label rows/counts/form states understandable and accessible

**Files:**

- Modify: Flutter `lib/core/components/pg_ingredient_tile.dart`
- Modify: Flutter `lib/core/components/pg_ingredients_card.dart`
- Modify/Test: Flutter `test/core/components/pg_ingredient_tile_test.dart`

- [x] Add failing tests for logical counts, indentation, visible `Form not disclosed`/`Form listed · not yet assessed`/`Data needs review`, text-plus-color status, Semantics hierarchy, and score participation.
- [x] Implement label-first titles and lazy row rendering without counting headers as ingredients.
- [x] Verify the focused test and `flutter analyze`.

### Task 9: Separate analysis coverage from label completeness

**Files:**

- Modify: Flutter `lib/features/product_detail/v2/sections/label_confidence_helpers.dart`
- Modify: Flutter `lib/features/product_detail/v2/sections/label_confidence_section.dart`
- Modify/Test: Flutter `test/features/product_detail/widgets/label_confidence_card_test.dart`

- [x] Add failing tests for independent concepts and unavailable completeness on unsupported structures.
- [x] Rename existing mapped-coverage presentation to **Analysis coverage** and add a separate label completeness/match result derived only from ledger audit metadata.
- [x] Preserve the invariant that `mapped_coverage < 0.3` never displays safe or safe-sounding copy.
- [x] Verify the focused tests, `test/safety_invariants/low_coverage_not_safe_test.dart`, and `flutter analyze`.

### Task 10: Remove duplicate profile warnings at the final display boundary

**Files:**

- Modify: Flutter `lib/features/product_detail/v2/warnings_pipeline.dart`
- Modify/Test: Flutter `test/features/product_detail/v2/warnings_partition_test.dart`

- [x] Add a failing test with duplicate vitamin C/standard nutrient warnings from different upstream paths.
- [x] Dedupe after every profile-gating/fallback branch using a stable consumer-content identity.
- [x] Verify the focused test and `flutter analyze`.

### Task 11: Explain aggregate evidence and ingredient evidence without contradiction

**Files:**

- Modify: Flutter `lib/features/product_detail/v2/sections/evidence_section.dart`
- Modify: Flutter `lib/features/product_detail/v2/sections/score_breakdown_section.dart`
- Modify/Test: Flutter `test/features/product_detail/v2/sections/score_breakdown_section_v4_test.dart`

- [x] Add failing tests where the formula pillar is limited but one ingredient is strong.
- [x] Label the pillar formula-wide and ingredient evidence ingredient-specific; show coverage and exact-product evidence separately.
- [x] Verify focused evidence/score tests and `flutter analyze`.

## P1 — Make Product Identity Verifiable

### Task 12: Emit defensible label provenance and version metadata

**Files:**

- Modify: pipeline `scripts/build_final_db.py`
- Add: pipeline `scripts/label_record_contract.py`
- Modify/Test: pipeline `scripts/tests/test_build_final_db.py`

- [x] Add failing tests for deterministic formula fingerprinting, source record ID, source/update date when present, product status, label source URL, and history only for defensible lineage keys.
- [x] Implement stable canonical serialization and never synthesize dates/history.
- [x] Verify the focused file.

### Task 13: Add Label match and source-label access

**Files:**

- Add: Flutter `lib/features/product_detail/v2/sections/label_match_section.dart`
- Modify: Flutter `lib/features/product_detail/v2/product_detail_v2_connected.dart`
- Add: Flutter `test/features/product_detail/v2/sections/label_match_section_test.dart`

- [x] Add failing tests for source/ID/UPC/status/version/fingerprint, unavailable fields, image vs PDF actions, and no false “exact match” claim.
- [x] Implement the source surface adjacent to **What the label lists**.
- [x] Verify the focused test and `flutter analyze`.

### Task 14: Present formula history only when lineage is real

**Files:**

- Add: Flutter `lib/features/product_detail/formula_history_model.dart`
- Add: Flutter `lib/features/product_detail/widgets/formula_history_sheet.dart`
- Add: Flutter `test/features/product_detail/widgets/formula_history_sheet_test.dart`

- [x] Add failing tests for real snapshots, no-history copy, uncertain lineage suppression, and changed-row summaries.
- [x] Implement a read-only history model; do not infer chronology from names.
- [x] Verify the focused test and `flutter analyze`.

### Task 15: Add the Label / Analysis ingredient filter

**Files:**

- Modify: Flutter `lib/features/product_detail/v2/sections/ingredients_section.dart`
- Modify: Flutter `lib/features/product_detail/v2/product_detail_v2_connected.dart`
- Modify/Test: Flutter `test/features/product_detail/v2/product_detail_v2_connected_test.dart`

- [x] Add failing tests that Label is the default, Analysis shows only score-relevant rows, and switching filters never mutates score inputs or source order.
- [x] Implement an accessible segmented control with a clear row count for each view.
- [x] Verify the focused test and `flutter analyze`.

### Task 16A: Extend the local scan schema with non-health lineage

**Files:**

- Modify: Flutter `lib/data/database/tables/scan_history_table.dart`
- Generated: Flutter `lib/data/database/user_database.g.dart`
- Add: Flutter `test/data/database/scan_version_lineage_test.dart`

- [x] Add a failing schema test for optional formula fingerprint and catalog source version on scan-history rows.
- [x] Add only the nullable columns and regenerate Drift outputs.
- [x] Verify the focused schema test and `flutter analyze`.

### Task 16B: Migrate and query local scan lineage

**Files:**

- Modify: Flutter `lib/data/database/user_database.dart`
- Modify/Test: Flutter `test/data/database/scan_version_lineage_test.dart`

- [x] Add a failing migration/query test from the previous schema version.
- [x] Add a safe migration and query/write path; keep all profile/health data out of the record and out of Supabase.
- [x] Verify the focused database tests and `flutter analyze`.

## P2 — Close the Feedback and Operations Loop

### Task 17: Define private mismatch-report storage and RLS

**Files:**

- Add: Flutter `supabase/migrations/20260719_label_mismatch_reports.sql`
- Add: Flutter `test/safety_invariants/label_mismatch_rls_contract_test.dart`

- [x] Write a failing static contract test for auth-only insert/read, immutable ownership, owner-scoped client access, private bucket objects, and service-role reviewer access.
- [x] Add tables, enum/check constraints, storage policies, indexes, and no health/profile columns.
- [x] Verify the focused test plus `test/safety_invariants/no_health_in_supabase_test.dart`.

### Task 18: Build the report service and strict privacy payload

**Files:**

- Add: Flutter `lib/services/label_mismatch_report_service.dart`
- Add: Flutter `test/services/label_mismatch_report_service_test.dart`

- [x] Add failing tests for authentication, allowlisted categories, maximum three image files, retry-safe object paths, product/version metadata, and rejection of health/free-text fields.
- [x] Implement manifest-first persistence, private uploads, and server-verified pending-to-ready finalization with typed, idempotent retry behavior.
- [x] Verify the focused test and `flutter analyze`.

### Task 19A: Add the supported label-photo dependency

**Files:**

- Modify: Flutter `pubspec.yaml`
- Modify: Flutter `pubspec.lock`

- [x] Add the current supported `image_picker` package after checking official package documentation.
- [x] Run `flutter pub get`, `flutter analyze`, and the package resolution checks.

### Task 19B: Configure explicitly selected label-photo capture

**Files:**

- Modify: Flutter `ios/Runner/Info.plist`
- Modify: Flutter `android/app/src/main/AndroidManifest.xml`

- [x] Add accurate camera/photo usage descriptions and platform configuration only where required.
- [x] Run `flutter analyze` and `flutter build apk --debug`.

### Task 20: Add the authenticated mismatch-report UI

**Files:**

- Add: Flutter `lib/features/product_detail/widgets/label_mismatch_sheet.dart`
- Modify: Flutter `lib/features/product_detail/v2/sections/label_match_section.dart`
- Add: Flutter `test/features/product_detail/widgets/label_mismatch_sheet_test.dart`

- [x] Add failing tests for sign-in gating, structured categories, three named photo slots, consent copy, upload/retry/success states, and no free-text health field.
- [x] Implement the sheet and CTA without automatically submitting or changing catalog data.
- [x] Verify the focused test and `flutter analyze`.

### Task 21: Add reviewer-only mismatch triage access

**Files:**

- Add: Flutter `supabase/functions/review-label-mismatch/index.ts`
- Add: Flutter `test/safety_invariants/label_mismatch_reviewer_access_test.dart`

- [x] Add a failing static/backend contract test proving normal clients cannot list reports or mint photo URLs, while the authenticated reviewer function uses server-held service-role authority to return short-lived signed URLs.
- [x] Implement explicit reviewer authorization, allowlisted response fields, audit logging metadata, ready-only review, and race-safe stale-upload cleanup with no profile/health joins.
- [x] Verify the focused contract test and Deno type-check.

### Task 22: Add privacy-allowlisted trust telemetry

**Files:**

- Add: Flutter `lib/services/label_trust_analytics.dart`
- Modify: Flutter `lib/services/analytics_service.dart`
- Add: Flutter `test/services/label_trust_analytics_test.dart`

- [x] Add failing tests for exact event names/keys and rejection/redaction of UPC, product name, label text, photo path, and every health/profile field.
- [x] Implement consent-gated local events for source opens, filters, form states, review states, and report outcomes.
- [x] Verify the focused test plus existing analytics/privacy tests and `flutter analyze`.

### Task 23: Add label-trust operations metrics

**Files:**

- Modify: pipeline `scripts/dashboard/data_loader.py`
- Modify: pipeline `scripts/dashboard/views/quality.py`
- Modify/Test: pipeline `scripts/tests/test_dashboard_smoke.py`

- [x] Add failing tests for aggregate-only label completeness, display dispositions, form states, integrity failures, formula-history coverage, mismatch outcomes, zero-row handling, and category/brand breakdowns.
- [x] Implement dashboard cards/tables and category/brand slices without raw report photos, health data, or user identifiers.
- [x] Verify the focused test and dashboard smoke checks.

## Final Integration and Release Verification

### Task 24: Run the full cross-repository trust gate

**Files:**

- Modify: Flutter `SPRINT_TRACKER.md` only after every gate passes.

- [ ] Run pipeline `scripts/test.sh fast` and `scripts/release_full.sh`.
  - Deferred by explicit user request; the five changed pipeline modules passed a pinned 373-test slice without rebuilding the catalog.
- [ ] Run Flutter `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, and `flutter test`.
  - Full tests passed 2,347/2,347; changed Dart files are format-clean; the repository-wide formatter still reports 40 pre-existing files outside this change.
- [x] Run Flutter `flutter build apk --release`.
- [x] Inspect both repository diffs for unintended score changes, safety-copy regressions, health-data persistence, generated artifacts, and files outside this plan.
- [x] Update the sprint tracker with exact test counts/commands, remaining deployment steps, and any external migration that is coded but not yet applied.
