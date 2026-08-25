# Submission Loop Hardening Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the shipped missing-product / label-mismatch loop so users can submit cleanly, reviewers can match or approve without typing a label from scratch, and a later holdout-gated extract draft can be loaded without a second store rebuild.

**Architecture:** Three batches. Batch 1 is Flutter-only (GTIN identity, validation, status copy, resubmit lineage, consent). Batch 2 is the review contract (disclosure + deep schema + open queue + fail-closed identity check + DB reviewer allowlist + product picture) with one additive migration and Edge deploys. Batch 3 is console-only, provider-neutral extraction after a catalog release and device E2E. Reviewer identity is `auth.uid()`; service role cannot approve. Known NIH UPCs never mint `PG_SUB_…` without a fresh `no_match_verified`.

**Tech Stack:** Flutter/Dart, Drift, Supabase Edge (Deno), Postgres, dsld_clean Python (`scripts/test.sh fast`), local `scripts/submission_review/` console, `scripts/submission_review/extraction/` adapters (Batch 3 only; paid/local, never free-tier).

**Spec:** `docs/superpowers/specs/2026-08-25-submission-ai-review-design.md`

**Do not start Batch 3 until the release gate in this file is checked off.**

---

## File map

### Batch 1 (PharmaGuide ai)

| File | Role |
|---|---|
| `lib/services/gtin.dart` | Canonical GTIN parse, check digit, UPC-E expand, lookup candidates |
| `test/fixtures/gtin_golden.json` | Shared vectors (copy into dsld_clean with checksum test) |
| `lib/services/product_submission_service.dart` | Import gtin; `resubmission_of` on create |
| `lib/features/scanner/manual_barcode_sheet.dart` | Width + check digit before submit |
| `lib/features/scanner/scanner_screen.dart` | Pass symbology into GTIN identity |
| `lib/features/scanner/missing_product_submission_sheet.dart` | Validate at open; facts stay; consent |
| `lib/data/database/core_database.dart` | Lookup candidates include UPC-E expansion |
| `lib/features/contributions/product_submissions_screen.dart` | Headline split; resubmit CTA |
| `lib/services/pending_submission_intent.dart` | 60 min + kind |
| `lib/features/product_detail/widgets/label_mismatch_sheet.dart` | Intent + consent |
| `lib/app.dart` | Consume intent by kind |
| `supabase/migrations/<ts>_resubmission_of.sql` | Column + create RPC arg |

### Batch 2 (app edge + dsld_clean console)

| File | Role |
|---|---|
| `supabase/functions/review-product-submissions/schema.ts` (new) | Deep `manual_label_v1` |
| `supabase/functions/review-product-submissions/index.ts` | open list, pagination, record_match, picture upload, user-JWT `transition` |
| `supabase/functions/cleanup-product-submissions/index.ts` | Also purge reviewer-image objects |
| `supabase/migrations/<ts>_submission_review_v2.sql` | allowlist table, replaced review RPC (no `p_reviewer_id`), match history, picture columns, reviewer images + `source_rights`, `usage jsonb` |
| `scripts/submission_review/serve.py` | Local UPC index + built-at + freshness |
| `scripts/submission_review/static/{app.js,index.html,canonical.js,styles.css}` | Cards, editor, picture, queue, rights attestation |
| `scripts/product_submission_import.py` | Schema parity + WebP + index + thumbnail backfill |
| `scripts/tests/test_submission_review_server.py` | Index + identity cards |

### Batch 3

| File | Role |
|---|---|
| `scripts/submission_review/extraction/` | `LabelDraftExtractor` + gemini / openai / paddleocr adapters |
| `scripts/submission_review/HOLDOUT.md` | Frozen acceptance criteria **before** any provider run |
| `scripts/submission_review/serve.py` | `POST /api/extract` (interface only) |
| `scripts/submission_review/static/app.js` | Load AI draft, confidence |

---

## Batch 1

### Task 1: Golden GTIN fixture + `gtin.dart`

**Files:**
- Create: `lib/services/gtin.dart`
- Create: `test/fixtures/gtin_golden.json`
- Test: `test/services/gtin_test.dart`

- [x] **Step 1: Write the fixture and failing tests**

Include at least: valid UPC-A, EAN-13, EAN-8, UPC-E (raw + expanded + canonical GTIN-14), invalid check digit, 9–11 digit rejects, GS1 zero-pad equivalents. UPC-E vectors must prove expansion is used for lookup **and** submit identity.

- [x] **Step 2: Run RED**

Run: `flutter test test/services/gtin_test.dart`

- [x] **Step 3: Implement `GtinIdentity.parse` / `expandUpcE` / `isValidGtin`**

Scanner symbology is an input, never inferred from “EAN-8 never starts with 0”. Manual 8-digit: valid GTIN-8 stays EAN-8; also add UPC-E expansion to `lookupCandidates` when that expansion’s check digit is valid.

- [x] **Step 4: GREEN, then commit**

### Task 2: Thread GTIN through scanner, manual entry, lookup, submit

**Files:**
- Modify: `lib/features/scanner/scanner_screen.dart`
- Modify: `lib/features/scanner/manual_barcode_sheet.dart`
- Modify: `lib/features/scanner/missing_product_submission_sheet.dart`
- Modify: `lib/data/database/core_database.dart`
- Modify: `lib/services/product_submission_service.dart` (use `gtin.dart` instead of private `_isValidGtin`)
- Test: existing scanner / manual / submission sheet tests + new cases

- [x] **Step 1: Failing tests** — manual 9-digit rejected with inline copy; invalid GTIN never opens capture; UPC-E lookup uses expansion; submit-time `invalidUpc` uses the same copy as `label_mismatch_action.dart`.

- [x] **Step 2: Implement minimum wiring**

- [x] **Step 3: `flutter test` on the touched test files — GREEN**

### Task 3: Duplicate headline + resubmit CTA (UI)

**Files:**
- Modify: `lib/features/contributions/product_submissions_screen.dart`
- Test: `test/features/contributions/product_submissions_screen_test.dart`

- [x] **Step 1: Failing tests** for `alreadyInCatalog` / `duplicateSubmission` headlines; Try-again present for `photoQuality`, absent for `notASupplement`.

- [x] **Step 2: Implement headline switch + CTA that calls a callback with UPC / product id**

- [x] **Step 3: GREEN**

### Task 4: `resubmission_of` migration + create RPC + service

**Files:**
- Create: `supabase/migrations/<timestamp>_product_submission_resubmission_of.sql`
- Modify: `lib/services/product_submission_service.dart`
- Modify: create-RPC in the latest product-submission migration (replace function, do not edit 20260731 in place)
- Test: `test/safety_invariants/product_submission_pipeline_contract_test.dart`
- Test: `test/services/product_submission_service_test.dart`

- [x] **Step 1: Contract tests** — RPC accepts `resubmission_of` only for own rejected row; wrong owner / non-rejected / missing id fail closed.

- [x] **Step 2: Migration + Dart payload**

- [x] **Step 3: Wire CTA** — missing_product reopens capture with that UPC; label_mismatch reopens mismatch sheet; both pass `resubmission_of`.

### Task 5: Facts step no auto-advance

**Files:**
- Modify: `lib/features/scanner/missing_product_submission_sheet.dart`
- Test: `test/features/scanner/missing_product_submission_sheet_test.dart`

- [x] **Step 1: Change `_captureRequiredEvidence` helper tests** — first facts shot stays; second angle appends; combined-panel dialog fires once on Continue.

- [x] **Step 2: Implement** — auto-advance remains for front; facts wait for Continue.

### Task 6: Intent TTL + mismatch kind

**Files:**
- Modify: `lib/services/pending_submission_intent.dart`
- Modify: `lib/features/product_detail/widgets/label_mismatch_sheet.dart`
- Modify: `lib/app.dart`
- Test: pending intent tests + mismatch sheet tests

- [ ] **Step 1: Tests** — 60 min TTL, consume-once, missing kind = missing_product, label_mismatch routes via `findById` or drops.

- [ ] **Step 2: Implement save-before-auth on mismatch; consume routes by kind.**

### Task 7: Combined consent copy

**Files:**
- Modify: `missing_product_submission_sheet.dart` and `label_mismatch_sheet.dart` privacy/consent strings
- Test: pinned-copy tests in both suites

Must include: private review, third-party AI may read the label, human approves every entry, front photo may be published (including crop), EXIF stripped, no PHI in pixels.

### Task 8: Batch 1 verification

- [ ] `flutter test` on all files touched in Batch 1
- [ ] `make check` in PharmaGuide ai
- [ ] Commit Batch 1 as one PR (or stacked commits per task)

---

## Batch 2

### Task 9: Deep schema module + disclosure enum

**Files:**
- Create: `supabase/functions/review-product-submissions/schema.ts`
- Modify: `index.ts` `validateApprovedPayload` to call it
- Modify: `scripts/product_submission_import.py` `_validate_label_payload`
- Create: shared malformed/valid JSON fixtures; checksum test in both repos

- [ ] **Step 1: Deno tests** — empty ingredient object rejected; blend nesting; units; `unverified` disclosure rejected; `present` requires otherIngredients text; `declared_none` requires empty.

- [ ] **Step 2: Implement schema; importer parity**

- [ ] **Step 3:** `deno test --allow-env supabase/functions/` and `bash scripts/test.sh fast -k "product_submission_import or manual_label"` in dsld_clean

### Task 10: Open queue + cursor pagination

**Files:**
- Modify: `review-product-submissions/index.ts`
- Modify: `scripts/submission_review/static/app.js`
- Test: Deno list tests + `test_submission_review_server.py` if it stubs list

- [ ] `status: "open"` filters `submitted` + `under_review`
- [ ] `after: {submitted_at, id}` cursor
- [ ] total open count in response
- [ ] Console default Open, Load more, render count

### Task 11: Allowlist table, `auth.uid()` review RPC, fail-closed identity

**Files:**
- Create: `supabase/migrations/<ts>_submission_review_v2.sql` (do not edit 20260731 / 20260824)
- Modify: `supabase/functions/review-product-submissions/index.ts` (`transition` via **user JWT client**, not `admin.rpc`; new `record_match`)
- Test: `test/safety_invariants/product_submission_reviewer_access_test.dart`
- Test: `test/safety_invariants/product_submission_pipeline_contract_test.dart`

- [ ] **Allowlist table** — `ENABLE` + `FORCE RLS`, **no policies**, `REVOKE ALL` from `PUBLIC, anon, authenticated, service_role`. Membership via migration / operator SQL only.
- [ ] **Replace `review_product_submission`** — drop `p_reviewer_id`; identity and `reviewed_by` from `auth.uid()` + table membership (same pattern as `finalize_product_submission`). `GRANT EXECUTE` to `authenticated` only; revoke `service_role` and `anon`.
- [ ] **Edge `transition`** uses the user client. Env `PRODUCT_SUBMISSION_REVIEWER_IDS` remains the early 403. Gate-ordering test still requires byte-verify before the RPC, now against the user-client call.
- [ ] **`record_match`** outcomes: `catalog_match` / `dsld_match` / `identity_ambiguous` / `no_match_verified` / `not_this_product` (required reason, history retained). Exact canonical GTIN-14 only. Index built-at stored on the check.
- [ ] **Approve precondition:** latest check is `no_match_verified` and index age within the 60-day block. Otherwise 400. `dsld_match` Duplicate immediately after `refresh-ids` lands in canonical raw — do not wait for OTA.
- [ ] Update the two pinned tests in **this** PR (action/field allowlist ~35–46, transition fields ~166–184, `admin.rpc` assertions, ~388 service-only grants).

### Task 12: Local UPC index in `serve.py`

**Files:**
- Modify: `scripts/submission_review/serve.py`
- Test: `scripts/tests/test_submission_review_server.py`

Index keys = same GTIN candidate set as Task 1 (load golden JSON; checksum against Flutter fixture). **Exact canonical GTIN-14 equality only.**

Sources: `--catalog-db` products_core + configurable enriched-corpus dir (DSLD input including excluded).

- [ ] Surface **index built-at** in the console.
- [ ] Freshness constants **in this file**: warn at 30 days, block at 60. Blocked index ⇒ cannot `record_match` `no_match_verified` ⇒ Approve stays rejected (shared with Task 11).
- [ ] Cards: shipped → Duplicate; corpus-only → Import + `refresh-ids` then Duplicate immediately; **ambiguous never auto-picks**; no exact hit → `no_match_verified`; wrong hit → audited `not_this_product`. Use as draft fills the editor only.

### Task 13: Console editor + polish + picture + cleanup

**Files:**
- `static/index.html`, `app.js`, `canonical.js`, `styles.css`
- review function: signed upload for reviewer images; approve accepts exactly one picture source for `missing_product`
- Migration: picture UUID columns **without** FK to photos; `product_submission_reviewer_images` including `source_rights`
- Modify: `supabase/functions/cleanup-product-submissions/index.ts`
- Test: `test/safety_invariants/product_submission_reviewer_access_test.dart` (picture keys on `transition`; cleanup must name the reviewer-image bucket)
- Test: `test/safety_invariants/product_submission_retention_test.dart` if it pins the photos bucket only

- [ ] Structured editor: forms, nested rows, Other Ingredients, statements, disclosure control — same object as raw JSON
- [ ] Product picture radio; crop/rotate export JPEG (`source_rights = user_evidence_crop`, no extra attestation); upload replacement requires `operator_photo` / `manufacturer_provided` / `licensed` attestation
- [ ] Lightbox with ✕; signed URL refresh ~4.5 min; edge errors visible; terminal buttons disabled
- [ ] Cleanup purges reviewer-image objects on the same 90-day post-promotion claims as evidence photos

### Task 14: Importer copies catalog WebP **and** registers it

**Files:**
- Modify: `scripts/product_submission_import.py`
- Test: `scripts/tests/test_product_submission_import.py`

After materialize, download evidence or reviewer object then:

1. Write `scripts/dist/product_images/{product_id}.webp` (900 px, q=88)
2. Append `{product_id}` to `product_image_index.json` (this is what `sync_to_supabase.py` actually uploads)
3. `UPDATE products_core SET image_thumbnail_url = 'product-images/{product_id}.webp'` for that `PG_SUB_` row

Do **not** call `build_final_db.py:backfill_image_thumbnails` (dead code, zero callers). Do not rely on `extract_product_images.py` (PDF-only probe). Failure of the image copy does not drop the label. Identity lock remains the RPC.

- [ ] Test asserts the WebP file **and** the index entry **and** the `image_thumbnail_url` column.

### Task 15: Batch 2 verification

- [ ] `supabase db reset` locally after migrations
- [ ] Deno tests
- [ ] `bash scripts/test.sh fast -k "submission or review or gtin or import"`
- [ ] Flutter safety-invariant tests that grep the edge/SQL sources (`product_submission_reviewer_access_test.dart`, `product_submission_pipeline_contract_test.dart`) — already updated in Tasks 11/13, re-run here
- [ ] Deploy `review-product-submissions` **and** `cleanup-product-submissions` once with Batch 2

---

## Release gate (human; not agent)

- [ ] User: `bash scripts/release_full.sh`
- [ ] Rebuild phone from `main` (existing 7 dart-defines / current device)
- [ ] Rescan a known in-catalog UPC (must not open capture as missing)
- [ ] Submit junk → reject `photo_quality` → push arrives → Resubmit CTA works
- [ ] **Stop.** Do not implement Batch 3 until this is checked.

---

## Batch 3 (only after the gate)

### Task 16: Holdout freeze + extract package

**Files:**
- Create: `scripts/submission_review/HOLDOUT.md` (**before** any provider run)
- Create: `scripts/submission_review/extraction/extractor.py` (`LabelDraftExtractor` + validation/usage plumbing)
- Create: `scripts/submission_review/extraction/gemini_adapter.py` (Gemini 2.5 Flash-Lite, paid)
- Create: `scripts/submission_review/extraction/openai_adapter.py` (GPT-5.4 nano pinned snapshot, strict Structured Outputs)
- Create: `scripts/submission_review/extraction/paddleocr_adapter.py` (PaddleOCR-VL local)
- Modify: `scripts/submission_review/serve.py` `POST /api/extract` (interface only)
- Modify: `static/app.js` Load AI draft + confidence badges
- Existing `record_extraction` Edge action (reviewer JWT)

- [ ] Freeze `HOLDOUT.md` acceptance criteria first: omissions, invented rows, numeric qty, units, blend nesting, other-ingredient disclosure, schema validity, human correction time. Explicit **“no provider qualifies”** outcome.
- [ ] Paid/local credentials for the benchmarked providers only. **Free tiers never see user photos.**
- [ ] Per-provider data-control preconditions (Gemini billing + logging off + ZDR requested + no search grounding; OpenAI ZDR or recorded abuse-retention acceptance; local N/A). Verify current terms at implementation; fail closed.
- [ ] Run adapters against the holdout. Record dated numbers in `HOLDOUT.md`. Select among **qualifiers** by accuracy → review-time → cost. Self-reported confidence is not acceptance evidence.
- [ ] Per-run confirmation; hash rebind; schema validate before store; idempotency `(submission_id, photo hashes, model, prompt_version)`; no silent fallback (reason on the extraction row if a different adapter is used).
- [ ] Persist generic `usage jsonb` (billable units, model/version, provider request id, latency, currency/rate snapshot, computed cost, privacy/ZDR confirmation). No model-specific DB columns.
- [ ] Privacy policy + App Store disclosure review checkbox before enabling the production console button.
- [ ] Never send reviewer-supplied product pictures to the model.

---

## Explicitly not in this plan

Free-tier AI providers on user photos; extract-on-finalize; auto-approve; OFF lookup; points ledger; failed-scan inbox.
