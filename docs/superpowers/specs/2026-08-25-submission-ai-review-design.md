# Submission loop hardening + AI review — Unified plan

**Date:** 2026-08-25

**Status:** Revised after external review, 2026-08-25 — implement Batch 1
only after the user re-reviews this file and the checklist. Do not
enable extraction until after the release + device E2E gate.

**This document supersedes** the earlier draft of this file and is the
merge of (1) the Grok/Claude submission-loop hardening plan and (2) the
AI-draft / human-verify / product-picture design. Parent contract:
`docs/superpowers/specs/2026-07-30-product-submission-pipeline-design.md`.

**Executable checklist:**
`docs/superpowers/plans/2026-08-25-submission-loop-hardening.md`

## Decision

Users still only send photos. Reviewers still only publish through
`review_product_submission` + the existing Clean → Enrich → Score →
release train. AI cannot approve. Auto-approve stays off.

Work ships in three batches. **Fix the capture/status/console contract
first, extract later.** Extraction is a gated, provider-neutral pilot
after one catalog release and one phone rebuild.

## How this amends the parent contract

This plan **extends** the 2026-07-30 pipeline spec. It does not replace
it. Two parent non-goals / invariants are narrowed here, and only these:

1. **“No public label-photo URLs”** (parent §10) is narrowed to:
   consented publication of the **front-identity** photo (or a reviewer
   crop/replacement) as the catalog product image. All other evidence
   photos stay private, owner-scoped, and retention-bounded.
2. **Reviewer allowlist via `PRODUCT_SUBMISSION_REVIEWER_IDS`** remains
   the Edge early gate. Batch 2 adds a **database-enforced twin**: a
   locked-down allowlist table, and `review_product_submission`
   deriving reviewer identity from `auth.uid()` only (no
   `p_reviewer_id`). Both layers fail closed on drift.

Every other parent invariant stands: no anonymous submissions, no user
narrative, no automatic AI approval, no second catalog or scorer, no
OFF ingestion in this plan.

## Locked product decisions

1. A human always clicks Approve in v1. Reviewer identity is
   `auth.uid()` plus allowlist-table membership. No caller-supplied
   reviewer id. Auto-approve is a later, **separately approved**
   policy under a **distinct machine principal** — forging a human
   allowlist identity is structurally impossible after Batch 2.
2. Catalog product picture: chosen `front_identity` evidence photo, or
   a reviewer crop/replacement. Evidence photos stay immutable. Copy
   into `product-images/{product_id}.webp` at **release**, including
   the index entry and `image_thumbnail_url` backfill that the
   existing DSLD image path actually uses.
3. One consent checkbox covers: private review, front photo may be
   published (including crop), and photos **may be processed by
   third-party AI to help read the label; a human reviewer approves
   every entry**. Ship this copy in Batch 1 so extraction can wire
   later without another store rebuild. Vendor-neutral; no change
   when swapping extract adapters.
4. Reviewer may Approve as-is, Reject, Duplicate, or patch fields then
   Approve. The AI draft stays in `product_submission_extractions`.
5. Match first against **local** indexes, not live NIH from an Edge
   Function. Missing-product Approve requires a **fresh, positive,
   recorded identity check** (`no_match_verified`). Exact canonical
   GTIN-14 only. Known NIH / catalog UPCs never mint `PG_SUB_…`.
6. Enhance `scripts/submission_review/`. Do not build a second console.
7. Model self-reported confidence is a reviewer cue only. It is never
   acceptance evidence and never publishes.
8. Empty Other Ingredients can be legitimate. Do not block Approve on
   emptiness. Use a typed disclosure state (§8).
9. Extraction is **provider-neutral** behind
   `scripts/submission_review/extraction/`. Free tiers never see user
   photos. No vendor is pinned in this spec; Batch 3 benchmarks
   adapters against frozen holdout criteria and may conclude **no
   provider qualifies**.
10. Scanner symbology wins for UPC-E vs EAN-8. Do not encode
    “EAN-8 never starts with 0”. Manual 8-digit: check digit + try both
    lookup candidates; submit one canonical identity.

## Sequence

| When | What |
|---|---|
| **Batch 1** | App GTIN identity, entry validation, duplicate headline, resubmit+lineage, facts stay, 60 min intent + mismatch, combined consent. One Flutter PR. Rides the pre-release rebuild. |
| **Batch 2** | Disclosure state, deep `manual_label_v1` schema, open queue + pagination, local identity index + fail-closed Approve, DB reviewer allowlist + `auth.uid()` RPC, console polish, product-picture crop/replace + rights/retention, importer picture copy **through `product_image_index.json`**. One additive migration + one `review-product-submissions` deploy. |
| **Release gate** | User runs `release_full.sh`. Rebuild the phone. Device E2E (rescan + reject + resubmit CTA). |
| **Batch 3** | Console-only extract package + holdout. Enable only after accuracy + privacy gates. Human Approve only. |
| **Later** | Extract-on-finalize Edge Function; auto-approve only under a distinct machine principal and a separately approved policy. Not this plan. |

## Out of scope

- Unified failed-scan operator inbox
- Open Food Facts lookup
- Points → server ledger (required before any redemption)
- APNs old-key rotation
- Auto-approve implementation
- Label-mismatch AI drafts (v1 extract is `missing_product` only)
- A new reviewer web app
- Free-tier AI providers on user photos
- Extract-on-finalize

---

## Batch 1 — App fixes

Repo: PharmaGuide ai. No extraction. Consent copy **does** mention AI.

### 1. GTIN one identity

New `lib/services/gtin.dart`:

```dart
class GtinIdentity {
  final String rawDigits;
  final GtinSymbology detectedSymbology; // upcE, ean8, upcA, ean13, unknown
  final String canonicalGtin14;
  final List<String> lookupCandidates;
}
```

Hoist `_isValidGtin` here. `expandUpcE()` per GS1; re-verify check digit
after expansion.

- Camera: thread `BarcodeFormat` (upcE / ean8 / upcA / ean13). UPC-E
  expands to UPC-A; that expanded form is the identity for **lookup and
  submit**.
- Manual 8-digit: do not assume leading `0` ⇒ UPC-E. If the 8-digit
  string is a valid GTIN-8, keep it as EAN-8 **and** add a UPC-E
  expansion to `lookupCandidates` when that expansion’s check digit
  is valid. Submit `canonicalGtin14` / the primary raw identity the
  validator selected (document in the golden fixture).
- `core_database.dart` `findAllByUpc` uses the same candidate set
  (keep existing zero-pad variants **plus** UPC-E expansion).

**Golden vectors:** one JSON fixture consumed by Dart, Deno, and Python
tests (pipeline copy checksum-pinned). Python `normalize_upc` + SQL
CHECK stay width-based; vectors pin cross-layer equivalence.

### 2. Entry-point validation

- `manual_barcode_sheet.dart`: `_isValid` = width ∈ {8,12,13,14} +
  check digit; inline error. 9–11 digit codes never submit.
- Missing-product sheet: validate at open (copy pattern:
  `label_mismatch_action.dart`). Never start capture on an invalid
  code. Map submit-time `invalidUpc` to the same copy as backstop.

### 3. Duplicate headline

Switch on `resolutionCode`:

- `alreadyInCatalog` → “Already in the catalog”
- `duplicateSubmission` → “Already on its way”
- null / other → keep current fallback

### 4. Resubmit with lineage

Additive migration: `resubmission_of uuid REFERENCES product_submissions(id)`
plus create-RPC arg. Must reference the caller’s own rejected
submission.

App: “Try again with new photos” on rejected cards where
`resolutionCode?.resubmittable == true`. Missing-product reopens
capture for that UPC; correctable label-mismatch reopens the mismatch
flow. Both pass `resubmission_of`.

Present for `photoQuality` / `missingPanel` / `labelUnreadable` /
`other`. Absent for `notASupplement` / `alreadyInCatalog` /
`duplicateSubmission`.

### 5. Facts step

After a passing facts shot, **stay** on Facts with “Add another angle”
+ primary Continue. Combined-panel dialog moves to Continue. Wrap copy
stays honest.

### 6. Sign-in intent

TTL 15 → 60 minutes. Payload gains `kind`:
`missing_product{upc}` | `label_mismatch{dsld_id}`. Missing kind =
missing_product (legacy). `label_mismatch_sheet.dart` saves intent
before pushing auth. Consume in `app.dart` routes by kind
(label_mismatch via `coreDatabase.findById`; missing product → drop).

### 7. Consent copy

Capture **and** label-mismatch privacy panels:

- account id, barcode, selected photos go privately to PharmaGuide
- EXIF stripped; no pharmacy stickers / PHI in the pixels
- photos **may be processed by third-party AI to help read the label;
  a human reviewer approves every entry**
- if approved, the front-label photo (including a crop) may be
  published as the product image

One checkbox. Pinned-copy tests updated. Reviewer-uploaded replacements
from another source are staff-sourced and do not need a second user
checkbox.

---

## Batch 2 — Contract, console, edge

### 8. Typed other-ingredients disclosure

`manual_label_v1` gains:

`otherIngredientsDisclosure ∈ {present, declared_none, included_on_facts_panel, unverified}`

Approve (edge `transition` **and** `product_submission_import.py`):

- state ≠ `unverified`
- supporting `photo_id` on the submission
- `present` ⇒ non-empty `otherIngredients`
- `declared_none` / `included_on_facts_panel` ⇒ empty
  `otherIngredients` plus reviewer confirmation (console checkbox is
  not sufficient; the payload field is)

This replaces any “block if Other Ingredients empty” idea.

### 9. Deep `manual_label_v1` schema

One versioned schema module next to
`review-product-submissions/index.ts`, shared conceptually with the
importer via the same fixture vectors (valid + malformed):

- ingredient identity + displayed name
- quantity + unit types
- blend ownership / nesting
- serving sizes
- disclosure state (item 8)
- statements
- photo provenance where claimed

Today `validateApprovedPayload` only checks `ingredientRows` is 1..200
objects (`index.ts` ~136–140). That is the gap.

Console structured editor and raw JSON mutate **one** canonical object.

Widening `transition` allowlisted keys (picture ids, match fields)
**breaks**
`test/safety_invariants/product_submission_reviewer_access_test.dart`
(explicit actions/fields ~35–46 and resolution contract ~166–184).
Update those assertions in the **same PR**, not at batch-end.

### 10. Queue: open default + pagination

Edge `list`:

- `status: "open"` → `review_status IN ('submitted', 'under_review')`
- cursor `after` on `(submitted_at, id)`
- returns total open count
- default limit stays 1..100; console currently sends 100 — keep it

Console defaults to Open, shows the count, “Load more”. Deno tests.

The live bug is unfiltered oldest-first of **any** status, not 50 vs
100 (console already sends `limit: 100`; edge default is 50).

### 11. Local identity index — fail-closed Approve

`serve.py` builds a normalized UPC/GTIN index (same golden vectors,
**exact canonical GTIN-14 equality only** — no fuzzy or substring
hits) from:

1. the **enriched corpus** (full DSLD input, including
   excluded/quarantined)
2. the released catalog SQLite (`--catalog-db`)

Index **built-at** is stored and shown in the console. Freshness
constants live in `serve.py`: **warn at 30 days, block at 60**. The
corpus rebuilds with the release train; a 60-day-stale index means no
release in two months — investigate before minting identities.

`record_match` (reviewer JWT) records one of:

| Outcome | Meaning | Close path |
|---|---|---|
| `catalog_match` | Exact GTIN-14 hit in released catalog | Duplicate `already_in_catalog` + dsld id. Approve rejected. |
| `dsld_match` | Exact hit in corpus, not shipped | `dsld_api_sync.py refresh-ids --ids {id}` into canonical raw, then Duplicate **immediately** (do not wait for catalog OTA). App already gates “View product” until the next catalog update. Approve rejected. Multiple exact versions → `identity_ambiguous`; operator picks; never auto-first. **Use as draft** may fill the editor for photo comparison only. |
| `identity_ambiguous` | More than one exact match | Operator resolves explicitly. Approve rejected. |
| `no_match_verified` | No exact hit, with index built-at | Transcribe / extract. Approve allowed only if this is the **latest** recorded check **and** index age is within the 60-day block. |
| `not_this_product` | Audited override of a wrong NIH/catalog hit | Required reason; kept in match **history** (does not erase the prior row). Unblocks drafting. |

**Rule:** no `missing_product` Approve without a fresh, positive,
recorded identity check (`no_match_verified`, index not stale).
Missing index, stale index, `identity_ambiguous`, `catalog_match`,
or `dsld_match` ⇒ identity unresolved ⇒ RPC rejects Approve.

Residual risk (accepted, dated): a product NIH added after the last
corpus sync can still draft. Documented, not a reason to call live
NIH from the Edge Function. `DSLD_API_KEY` is not required for Batch 2.

Exact enum names may be refined in implementation; this rule does not
move.

### 11b. Approval is human-only by construction

Today `review_product_submission` takes `p_reviewer_id` and is granted
to `service_role` only (v2 migration ~844–846, grants ~1220–1247). The
allowlist lives only in Edge env. Any service-key holder can approve
as any UUID.

Batch 2 **replaces** the function in a new migration (never edit the
old one in place):

- New table `product_submission_reviewers` (name may vary): membership
  is reviewer `auth.users` ids. House lockdown in the style of
  `product_submission_push_deliveries`: `ENABLE` + `FORCE ROW LEVEL
  SECURITY`, **no policies**, `REVOKE ALL` from
  `PUBLIC, anon, authenticated, service_role`. Membership changes only
  via migration / operator SQL (superuser).
- Drop `p_reviewer_id`. Reviewer identity — including `reviewed_by`
  on the audit row — is `auth.uid()` **and** a row in that table.
  Pattern: `finalize_product_submission` already uses `auth.uid()`.
- `GRANT EXECUTE` to `authenticated` only; `service_role` and `anon`
  revoked.
- Edge `transition` calls the RPC through the **user JWT client**,
  not the admin client. `PRODUCT_SUBMISSION_REVIEWER_IDS` stays the
  Edge early 403. Both layers fail closed on drift. The existing
  gate-ordering test (byte verify before RPC) survives; it must be
  updated to assert the **user-client** RPC, not `admin.rpc`.
- This **breaks** `product_submission_reviewer_access_test.dart`
  (admin.rpc assertions) and
  `product_submission_pipeline_contract_test.dart` (~388,
  service-only EXECUTE grants). Update them in the same PR.

Result: no service-key function (including any future intake) can
approve, and no caller can supply someone else’s identity.

### 12. Console polish

Transition buttons reflect terminal state; edge error text visible;
Start-review success visible; photo lightbox with ✕ (not a new tab);
signed-URL refresh ~4.5 min. Identity cards and index built-at /
freshness warnings from §11.

### 13. Product picture

On Approve of `missing_product`, exactly one source:

- `product_image_photo_id` (evidence photo on this submission), or
- `product_image_reviewer_object_id` (crop or uploaded replacement)

`label_mismatch` stays photo-optional (parent contract).

Reviewer crop/rotate or “upload a clearer front photo” stages a
private object at `{reviewer_id}/{submission_id}/{object_id}` — **not**
`{user_id}/{submission_id}/`. Hash recompute after download. Never an
extraction input. Blurry Supplement Facts still Reject
`photo_quality` / `label_unreadable`.

UUID columns have **no FK** to `product_submission_photos` (cleanup
must still delete manifests).

**Rights basis** on `product_submission_reviewer_images.source_rights`:

| Value | When | Attestation |
|---|---|---|
| `user_evidence_crop` | Crop/rotate of the submitter’s front photo | Inherits capture consent. No extra checkbox. |
| `operator_photo` | Reviewer-taken replacement | Console attestation required. |
| `manufacturer_provided` | Brand/manufacturer asset | Console attestation required. |
| `licensed` | Other licensed source | Console attestation required. |

Uploads without attestation fail closed. Crops do not need one.

**Retention:** `cleanup-product-submissions` today deletes only
`product-submission-photos` via photo manifests. Extend it to purge
reviewer-image objects on the same 90-day post-promotion claims.
The public catalog WebP remains. The new bucket otherwise has no
owner.

**Copy at release** inside `product_submission_import.py --fetch`
must follow the path images actually take today, or `PG_SUB_` rows
silently ship with no picture:

1. Write `scripts/dist/product_images/{product_id}.webp` (same knobs
   as `extract_product_images.py`: `MAX_WIDTH_PX = 900`, quality 88).
2. **Append** `{product_id}` to `product_image_index.json` in that
   directory. `sync_to_supabase.py` uploads **only** via that index
   (`load_product_image_index`, ~883–933). A lone WebP is skipped.
3. **Set** `products_core.image_thumbnail_url` to
   `product-images/{product_id}.webp` for that `PG_SUB_` row, using
   the same convention as
   `extract_product_images.py:backfill_image_thumbnail_urls`
   (~427–452). `extract_product_images.py` itself only loads
   `.pdf`-sourced DSLD rows (`load_products_from_db`, ~258–266) and
   is what `release_full.sh` runs — `PG_SUB_` rows are never in that
   probe. `build_final_db.py:backfill_image_thumbnails` (~10382) is
   **dead code with zero callers** — do not revive it.

`ProductImageResolver` already prefers `image_thumbnail_url`. Image
failure is non-fatal (placeholder). `--mark-promoted` stays
label-lineage only.

### Batch 2 schema extras

Additive migration (new file, never edit 20260731 / 20260824 in place):

- `resubmission_of` if not already in Batch 1’s migration
- `otherIngredientsDisclosure` lives in the approved JSON
- identity-check history + latest outcome (`catalog_match` /
  `dsld_match` / `identity_ambiguous` / `no_match_verified` /
  `not_this_product`) + index built-at metadata
- `approved_product_image_photo_id` /
  `approved_product_image_reviewer_object_id` (no FK)
- reviewer-images table (`source_rights`, hash, path) + bucket/prefix
- reviewer-allowlist table as in §11b
- replaced `review_product_submission` (no `p_reviewer_id`)
- nullable `usage jsonb` on `product_submission_extractions` for Batch
  3 (billable units, model/version, provider request id, latency,
  currency/rate snapshot, computed cost, privacy/ZDR confirmation).
  No model-specific columns.

Operator: `supabase db push`, deploy `review-product-submissions`
**and** `cleanup-product-submissions` once.

---

## Release gate (human)

1. `bash scripts/release_full.sh` (user).
2. Rebuild the phone from `main` (7 dart-defines; device as currently
   used).
3. Device E2E: rescan a known in-catalog UPC; submit a junk missing
   product; reject `photo_quality`; confirm up to 3 pushes; exercise
   Resubmit CTA.

Do not start Batch 3 until this is green.

---

## Batch 3 — Extraction pilot (console-only, gated, provider-neutral)

Preconditions: Batch 1 consent shipped, Batch 2 schema live, release
gate passed, **`HOLDOUT.md` acceptance criteria frozen before any
provider runs**, paid or local credentials only.

Package:

```
scripts/submission_review/extraction/
  extractor.py            # LabelDraftExtractor interface + shared validation/usage plumbing
  gemini_adapter.py       # Gemini 2.5 Flash-Lite (paid tier)
  openai_adapter.py       # GPT-5.4 nano (pinned snapshot, strict Structured Outputs)
  paddleocr_adapter.py    # PaddleOCR-VL local worker
```

`serve.py` `POST /api/extract` knows only `LabelDraftExtractor`. Batch
3 is a local Python server; adapters need no Edge compute.

Rules:

- **Holdout** covers: ingredient-row omissions, invented rows, numeric
  quantity accuracy, unit accuracy, blend ownership/nesting,
  other-ingredient disclosure, schema validity, human correction time.
  Explicit **“no provider qualifies”** outcome — then Batch 3 does not
  enable, and the plan revisits.
- Winner among qualifiers: accuracy first, human-review time second,
  cost third. Decision + numbers dated in `HOLDOUT.md`. Prices/terms
  verified live at benchmark time, never hardcoded here.
- Self-reported model confidence is a reviewer cue only — never
  acceptance evidence.
- `provider` / `model` / `prompt_version` already on every extraction
  row. Fill generic `usage jsonb` (Batch 2 column). No automatic
  fallback to another model without a recorded reason on that row.
- **Free tiers never see user photos.** Per-provider data controls are
  a Batch 3 precondition (verify current terms at implementation; fail
  closed where the provider offers a confirmation signal):
  - Gemini: billing-enabled project, developer logging/data-sharing
    off, ZDR requested, search grounding never enabled
  - OpenAI: ZDR approval **or** an explicit recorded acceptance of
    the default abuse-retention window; API account bills separately
    from ChatGPT
  - local: N/A
- Privacy policy + App Store privacy disclosures reviewed before the
  production console button is enabled.

Runtime: per-run reviewer confirmation; signed-URL download; per-photo
sha256 recompute; schema-constrained output validated against Batch 2
**before** store; prompt-injection (label text is data); idempotency
`(submission_id, photo hashes, model, prompt_version)`;
`record_extraction` under reviewer JWT; editor “Load AI draft” with
per-field `{photo_id, confidence}` badges.

Re-extract uses original evidence only. Wrong NIH hit uses the audited
`not_this_product` override from §11, then extract.

**Not in Batch 3:** extract-on-finalize Edge Function, auto-approve.

---

## Later (not this plan)

- Extract-on-finalize Edge Function (`cleanup`-style secret). It still
  cannot call `review_product_submission`.
- Auto-approve only with a **distinct machine principal** and a
  separately approved policy. Approving under a human allowlist
  identity would forge the audit record and is structurally impossible
  after §11b.

## Verification

- Flutter: focused tests per task; `make check` before claiming Batch 1
  done (re-measure; do not hardcode a pass count)
- Pipeline: `bash scripts/test.sh fast -k "submission or review or gtin"`
  in `dsld_clean` (never raw pytest)
- `deno test --allow-env` for the review function
- Shared golden GTIN + label-schema fixtures checksum-pinned across
  repos
- Local `supabase db reset` after the migration
- Device E2E at the release gate

**Pinned tests that this plan will break — update in the same PR:**

- `test/safety_invariants/product_submission_reviewer_access_test.dart`
  (~35–46 action allowlist; ~166–184 transition fields; `admin.rpc`
  assertions)
- `test/safety_invariants/product_submission_pipeline_contract_test.dart`
  (~388 service-only EXECUTE grants for `review_product_submission`)

## Critical files

**App:** `lib/services/gtin.dart` (new),
`lib/services/product_submission_service.dart`,
`lib/services/pending_submission_intent.dart`,
`lib/features/scanner/{manual_barcode_sheet,scanner_screen,missing_product_submission_sheet}.dart`,
`lib/features/contributions/product_submissions_screen.dart`,
`lib/features/product_detail/widgets/label_mismatch_sheet.dart`,
`lib/data/database/core_database.dart`, `lib/app.dart`, new migration

**Edge:** `supabase/functions/review-product-submissions/` (index +
schema module), `supabase/functions/cleanup-product-submissions/`

**Console / pipeline:** `scripts/submission_review/{serve.py,static/*,extraction/,HOLDOUT.md}`,
`scripts/tests/test_submission_review_server.py`,
`scripts/product_submission_import.py`,
`scripts/dsld_api_sync.py` (refresh-ids only, not a new importer)

## Key decisions

1. Claude’s batches are the execution order; this spec is the
   destination contract.
2. Local corpus match, not live NIH in v1. Approve requires a fresh
   recorded `no_match_verified`.
3. Numeric DSLD id for known NIH products; Duplicate as soon as
   `refresh-ids` lands in canonical raw. `PG_SUB_…` only after
   `no_match_verified`.
4. Extraction is provider-neutral and holdout-gated; free tiers never
   see user photos; “no provider qualifies” is a valid Batch 3 outcome.
5. Disclosure state, not empty-field gates.
6. Picture copy at release must write WebP **and** the image index
   **and** `image_thumbnail_url`. Evidence immutable. Reviewer
   replacements carry `source_rights`; cleanup owns their retention.
7. Reviewer identity is `auth.uid()` + DB allowlist. Service role
   cannot approve.
8. Extract after the phone rebuild, console-only, holdout-gated.
