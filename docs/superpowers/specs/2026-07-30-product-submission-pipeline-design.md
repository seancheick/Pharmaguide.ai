# Product Submission Pipeline — Implemented Design and Release Runbook

**Date:** 2026-07-30

**Status:** Code complete; not yet deployed to Supabase or released to users

**Decision:** One private submission system serves both catalog-label
corrections and missing products. AI may create an attributable draft, but
only a human reviewer can approve a canonical label and only the existing
pipeline can publish it.

## 1. System boundaries

There is one submission spine:

- `product_submissions` owns identity and lifecycle state.
- `product_submission_mismatch_details` owns the closed correction
  categories and existing DSLD lineage.
- `product_submission_missing_details` owns the one structured
  Other Ingredients assertion.
- `product_submission_photos` owns the immutable private photo manifest.
- `product_submission_extractions` stores versioned AI drafts and their
  provenance.
- `product_submission_approved_labels` stores the human-approved canonical
  `manual_label_v1` artifact.
- `product_submission_review_events` is the immutable review trail.

The implementation is in:

- `supabase/migrations/20260731144527_product_submission_pipeline_20260730.sql`
- `lib/services/product_submission_service.dart`
- `lib/services/product_submission_photo_service.dart`
- `supabase/functions/review-product-submissions/index.ts`
- `supabase/functions/cleanup-product-submissions/index.ts`
- `supabase/functions/delete-account/index.ts`
- pipeline `scripts/product_submission_import.py`
- pipeline `scripts/release_full.sh`

The retired `label_mismatch_*` runtime tables, bucket, service, and reviewer
function are migrated and removed. The unused `pending_products` table is
also removed after a fail-closed emptiness check; deployments with historical
rows must reconcile them explicitly instead of guessing free text and remote
image URLs into verified evidence. There is no second ingestion database,
scorer, or publication path.

## 2. User intake

Both flows require an authenticated account and explicit consent.

### Missing product

The scanner miss and manual-barcode miss open the same guided sheet. The
submission requires:

1. a valid GTIN-8, GTIN-12/UPC-A, EAN-13, or GTIN-14;
2. a front-label photo;
3. a Supplement Facts photo; and
4. an Other Ingredients photo or an explicit assertion that no such panel
   appears on the label.

### Label mismatch

Product Detail sends the existing catalog identity and one or more values
from the closed mismatch-category enum. Photos are optional and use the same
private photo service as the missing-product flow.

Neither flow accepts narrative text. The app does not send the user's health
profile, medications, conditions, allergies, or supplement stack.

Before upload, selected images are decoded and re-encoded without EXIF
metadata. The UI warns the user not to photograph pharmacy stickers, names,
prescription numbers, or other visible personal information. Re-encoding
cannot remove text that is visible in the pixels.

## 3. State model

Three concerns remain orthogonal:

- upload: `pending`, `ready`, `cleaning`;
- editorial review: `submitted`, `under_review`, `approved`, `rejected`,
  `duplicate`;
- publication: `promoted_catalog_version` plus `promoted_at`.

A row cannot look published merely because review finished. Promotion is
recorded only after the exact pipeline-owned product ID is proven present in
the released catalog database.

Creation is transactional and idempotent. The client writes one typed
manifest before uploading bytes. Exact retries reuse the same UUID and are
accepted even after an ambiguous successful finalization; changed retries
fail closed.

Finalization verifies:

- caller ownership;
- required typed details;
- required photo slots;
- private Storage object path and owner;
- declared byte size; and
- declared MIME type; and
- the client-computed SHA-256 copied into immutable Storage custom metadata.

Before either recording an AI extraction or approving a submission, the
reviewer service downloads each now-immutable private object and recomputes
its SHA-256. The trusted boundary rejects any byte-size or digest mismatch.
Client manifest values and Storage metadata alone are never treated as proof
of byte identity.

Unknown statuses render unavailable rather than complete.

## 4. Privacy and access control

`product-submission-photos` is private. Object paths are:

`{user_id}/{submission_id}/{photo_slot}`

RLS restricts users to their own submission rows and manifests. Authenticated
clients receive only `SELECT` table access plus the two narrow create/finalize
RPCs. They cannot update review, extraction, approval, or publication fields.
The service role receives direct `SELECT` access only for the review queue;
every state change goes through an audited `SECURITY DEFINER` RPC. Photo
manifests, extraction drafts, approved payloads, and review events therefore
cannot be rewritten through an accidental raw service-role table mutation.

The reviewer Edge Function:

- authenticates the caller before constructing a service-role client;
- requires the caller ID in `PRODUCT_SUBMISSION_REVIEWER_IDS`;
- accepts only `list`, `record_extraction`, and `transition`;
- lists only `ready` submissions;
- issues five-minute signed photo URLs;
- rejects unknown request and approval fields;
- pins approval to `manual_label_v1`;
- enforces the same top-level manual-label field vocabulary and cardinality
  limits as the pipeline;
- canonicalizes and SHA-256 hashes the approved payload server-side; and
- never logs request bodies or photo URLs.

An extraction is only a versioned draft. Its provider, model, prompt version,
input-image hashes, field provenance, and optional confidence are retained.
No confidence value or model output can approve a record. The external model
invocation remains an operational adapter behind this boundary; configuring a
provider does not change the approval or publication contract.

## 5. Human review

The reviewer must inspect the private label evidence and either:

- move `submitted` to `under_review`;
- approve an exact `manual_label_v1` payload;
- reject it; or
- identify a duplicate.

Approval cannot happen directly from `submitted`, cannot omit reviewer
identity, cannot supply an unrecognized schema, and cannot be self-marked by
the user. The database serializes approval by catalog target and rejects a
second approved-but-unpromoted correction for that identity, preventing two
reviewers from racing different labels into one release. Review notes are
staff-only and never returned to the consumer status surface.

A duplicate decision must point to an approved, ready submission of the same
kind and exact UPC or DSLD target. The database rejects cross-kind and
cross-product duplicate links. If the target owner later deletes their
account, the historical duplicate status remains but the self-reference is
cleared, so one user's contribution can never prevent another user's account
deletion.

The reviewer may create a correction for an existing numeric DSLD ID or a new
missing-product payload. A label mismatch keeps the existing DSLD identity. A
missing product receives the deterministic identity:

`PG_SUB_{SUBMISSION_UUID_WITHOUT_HYPHENS}`

## 6. The only publication path

The pipeline release preflight walks the service-only approved-export RPC
with a stable `(approved_at, submission_id)` cursor. This prevents previously
materialized but not-yet-promoted approvals from filling the first page and
starving newer work.
`scripts/product_submission_import.py` then:

1. verifies UUIDs, GTIN, schema, canonical JSON, SHA-256, reviewer
   provenance, allowed fields, required ingredients, serving sizes, and
   market status;
2. prevents reviewer-controlled identity and provenance overrides;
3. materializes an immutable manual label under
   `manual_labels/product_submissions/`;
4. writes a local immutable receipt; and
5. safely recovers if a process stopped after the atomic label write but
   before the receipt write.

Fresh labels run through the existing:

`clean_dsld_data.py → enrich_supplements_v3.py → score_products_v4.py`

`rebuild_dashboard_snapshot.sh`, Supabase catalog upload, and Flutter bundle
import remain unchanged and authoritative. The adapter never enriches,
scores, or publishes on its own.

After cloud sync and Flutter bundle parity succeed,
`product_submission_import.py --mark-promoted` opens the released SQLite
catalog, proves the receipt's product ID exists in `products_core`, verifies
the core row's pinned detail-blob checksum, and requires that blob's
`label_record.source_record_id` to equal the reviewed submission UUID. This
lineage check is essential for corrections because the numeric DSLD identity
already existed before the corrected label shipped. Only then does the
adapter read the exact `db_version` and record promotion through a
service-only, idempotent RPC.

A later correction for the same DSLD product may replace the current manual
label only after the receipt owning those exact bytes has been promoted. Its
new submission UUID becomes the source record while the stable numeric
product ID and `dsld:{id}` lineage remain unchanged. Unpromoted or
unreceipted bytes can never be overwritten.

## 7. Retention and account deletion

Private evidence is not permanent:

- never-finalized pending uploads are eligible after 24 hours;
- rejected or duplicate evidence is eligible 90 days after review;
- promoted evidence is eligible 90 days after promotion.

The cleanup worker leases at most 100 rows. It removes Storage objects first.
It verifies every returned object path and proves that omitted paths are
already absent, so a retry after a prior Storage success is idempotent while a
partial deletion still fails closed. Only verified Storage absence may delete
photo manifests. Final review and publication provenance are retained;
abandoned pending parents are deleted. Failed leases become retryable after
15 minutes.

Account deletion is remote-first:

1. authenticate the current account;
2. enumerate that user's private submission objects through a service-only
   RPC;
3. remove those objects through the Storage API;
4. delete the Auth user, allowing database cascades to remove user rows;
5. after confirmed server success, purge every local user store and return
   the app to signed-out state.

Normal sign-out intentionally retains on-device data for the same account.
A different account clears and adopts local ownership. Permanent account
deletion does not preserve a restore path.

## 8. Deployment order

Do not expose the UI before its private backend exists.

1. Back up the target Supabase database.
2. Confirm the legacy label-mismatch bucket and manifest table contain no
   un-migrated objects, and export/reconcile any historical `pending_products`
   rows. The migration fails closed if either legacy surface still carries
   unresolved data.
3. Apply `20260731144527_product_submission_pipeline_20260730.sql`.
4. Configure:
   - `PRODUCT_SUBMISSION_REVIEWER_IDS`
   - `PRODUCT_SUBMISSION_CLEANUP_SECRET`
   - `SUPABASE_SECRET_KEY` (preferred), the managed
     `SUPABASE_SECRET_KEYS.default`, or the legacy
     `SUPABASE_SERVICE_ROLE_KEY` during migration
   - `SUPABASE_PUBLISHABLE_KEY` (preferred), the managed
     `SUPABASE_PUBLISHABLE_KEYS.default`, or the legacy
     `SUPABASE_ANON_KEY` during migration
5. Deploy:
   - `review-product-submissions`
   - `cleanup-product-submissions`
   - `delete-account`
6. Schedule cleanup with a secret-authenticated server job. The checked-in
   Supabase function configuration disables platform JWT verification only for
   this worker because it authenticates the scheduler with the constant-time
   `x-cleanup-secret` boundary. Reviewer and account-deletion functions retain
   the platform's user-JWT verification.
7. Merge and release the pipeline adapter.
8. Merge and release the Flutter client.
9. Run the canaries below before beta distribution.

The pipeline release host requires `SUPABASE_URL` and prefers
`SUPABASE_SECRET_KEY`; the legacy `SUPABASE_SERVICE_ROLE_KEY` remains a
temporary fallback. Opaque `sb_secret_` keys are sent only as `apikey`, never
as a fabricated bearer JWT. `--skip-supabase` and Supabase dry-run modes do
not fetch new approvals, but can still process already-materialized labels.

## 9. Required canaries

Before beta:

- submit one missing product from a camera scan miss;
- submit one missing product from manual barcode entry;
- submit one label mismatch with no photo;
- submit one label mismatch with all three optional photos;
- interrupt an upload and verify the same UUID resumes;
- simulate a lost finalization response and verify exact retry succeeds;
- confirm another authenticated user cannot read rows or objects;
- confirm a non-allowlisted user cannot list or review evidence;
- record an extraction draft and prove it does not change review status;
- approve one missing product and one correction;
- run the normal release and prove both use the existing scorer;
- prove promotion is absent before catalog/bundle success and exact afterward;
- run the 90-day cleanup canary against disposable records;
- delete a disposable account and verify Storage, Auth, database rows, and
  local device stores are gone.

## 10. Deliberate non-goals

- No anonymous submissions.
- No user narrative field.
- No automatic AI approval.
- No public label-photo URLs.
- No second catalog or scoring engine.
- No Open Food Facts ingestion until its supplement coverage, ODbL
  obligations, image licensing, attribution, and database-combination impact
  receive a separate written decision.
- No retailer scraping without authorized terms or a feed agreement.
