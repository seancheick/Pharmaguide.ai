# Product Submission & Multi-Source Ingestion — Design

**Date:** 2026-07-30
**Status:** Design — awaiting approval. No migration has been applied.
**Decisions taken:** one backend serving both report-a-mismatch and
submit-a-missing-product; AI drafts, human approves everything.

---

## 1. Verified state of the world

Checked live against Supabase project `omayamxacvacrnvdvzhr`
(`PharmaGuide_Pipeline`) and the repo on 2026-07-30. The repository already
contains the code-complete migration
`supabase/migrations/20260719_label_mismatch_reports.sql` and reviewer
function; the blocker below is production deployment, not missing local code.

### The blocker

`showLabelMismatchSheet` is reachable in the app from
`label_match_section.dart:233` and `label_mismatch_action.dart:67`. The
service it calls expects:

| Client expects | Exists in prod |
|---|---|
| table `label_mismatch_reports` | **No** |
| table `label_mismatch_report_photos` | **No** |
| rpc `finalize_label_mismatch_report` | **No** |
| bucket `label-mismatch-report-photos` | **No** |

Until the existing migration and reviewer function are deployed to the
intended project, every production submission fails. The client and
privacy-preserving backend code exist; the production backend objects do not.

### Secondary findings

- **Both existing buckets are public** (`pharmaguide`, `product-images`).
  Label photos must not go anywhere public: a bottle photo can capture a
  pharmacy sticker, patient name, or Rx number.
- `pending_products` exists (0 rows) and is **orphaned** — nothing in `lib/`
  references it. Its design has three problems: a free-text
  `submitter_note`, a single `image_url` (cannot hold three label faces),
  and no extraction or provenance fields.
- `user_failed_scans` already queues every unresolved UPC locally, with a
  deliberate no-PII contract. This is the natural trigger for a submission
  prompt.
- `manual_labels/*.json` in `dsld_clean` is DSLD-shaped plus a
  `manual_product_provenance` block. **This is already the ingestion
  contract** — only 2 files exist, but the format is what matters.

---

## 2. The contract the client already sends

Any migration must match this exactly or the live feature stays broken.

**`label_mismatch_reports`** — `id` (client-generated uuid), `user_id`,
`dsld_id`, `upc`, `source_record_id`, `catalog_source_version`,
`formula_fingerprint`, `mismatch_categories` (text[]).

**`label_mismatch_report_photos`** — `report_id`, `user_id`, `photo_slot`,
`object_path`, `content_type`, `byte_size`.

**Storage object path** — `{user_id}/{report_id}/{slot}`.

**`finalize_label_mismatch_report(report_id) -> boolean`** — returns true
only when every declared photo path exists in storage. The client calls it
*before* uploading (so a retry after an ambiguous response short-circuits),
then again after upload. Both table writes must be idempotent on primary key
— the client relies on duplicate inserts being ignored for retry safety.

---

## 3. Unified schema

One submission spine, discriminated by `kind`. A missing-product submission
and a label-mismatch report differ only in whether `dsld_id` is null and
which structured fields are required.

```sql
create type submission_kind as enum ('label_mismatch', 'missing_product');
create type submission_status as enum (
  'draft',        -- row exists, photos not all uploaded
  'ready',        -- finalize() confirmed every photo present
  'extracting',   -- VLM job running
  'needs_review', -- extraction done, awaiting human
  'approved',     -- human approved, queued for the release train
  'promoted',     -- shipped in a catalog version
  'rejected',
  'duplicate'
);
```

`label_mismatch_reports` keeps its name and the exact columns above (the
client is already coded against it), and gains:

```sql
alter table label_mismatch_reports
  add column kind submission_kind not null default 'label_mismatch',
  add column status submission_status not null default 'draft',
  add column normalized_upc text generated always as (...) stored,
  add column extraction_json jsonb,          -- VLM output, manual_labels shape
  add column extraction_confidence numeric,  -- 0..1, advisory only
  add column extraction_model text,          -- provenance
  add column reviewed_by text,
  add column reviewed_at timestamptz,
  add column review_notes text,              -- STAFF-authored only
  add column promoted_catalog_version text,  -- proves the notification
  add column duplicate_of uuid references label_mismatch_reports(id);
```

### Deliberately absent: a user free-text field

`pending_products.submitter_note` must not carry forward. This is the same
class of risk as the standing rule against a free-text-to-Sentry box — users
will write "I take this for my thyroid," putting health data in a product
table. The existing `LabelMismatchCategory` enum already models this
correctly by having no `other` value. Structured input only.

`review_notes` is staff-authored and never user-writable (enforced by RLS).

### Deduplication

`normalized_upc` plus a partial unique index on open submissions collapses
the common case where many users submit the same missing product. A repeat
submission attaches as evidence rather than creating a new review item.

---

## 4. RLS and storage

```
INSERT  authenticated, WITH CHECK (auth.uid() = user_id AND status = 'draft')
SELECT  authenticated, USING (auth.uid() = user_id)
UPDATE  none for users — status transitions are service-role only
```

Users may never write `status`, `review_notes`, `extraction_*`, or
`promoted_catalog_version`. Enforce with a column-level grant, not only a
policy, so a compromised anon key cannot self-approve a submission into the
catalog.

**Bucket `label-mismatch-report-photos` must be created private.** Storage
policies scope both read and write to `(storage.foldername(name))[1] =
auth.uid()::text`, matching the `{user_id}/{report_id}/{slot}` path the
client already builds. Reviewers read through signed URLs minted by the
admin surface, never via public access.

Retention: photos are evidence for review, not a permanent asset. Delete on
`promoted` or `rejected` + 90 days. Worth writing down now because nobody
adds retention later.

---

## 5. Extraction and review

**AI drafts, human approves — all of it.** This matches the existing
fail-closed pattern in `medNutrientPublicationPolicy`, where only `verified`
records may display, persist, or notify.

Flow: `ready` → Edge Function enqueues → VLM reads the three photos and emits
`manual_labels`-shaped JSON into `extraction_json` → `needs_review` → human
approves → `approved` → picked up by the existing release train → `promoted`.

**Why a VLM rather than OCR:** a Supplement Facts panel is a visually
structured table with nesting. The Ritual manual label in the repo has a
`Probiotic Blend` row with `nestedRows` beneath it — classical OCR returns
text and loses that hierarchy, which is precisely the structure dosing and
interaction matching depend on.

**Confidence is advisory, never a gate.** It orders the review queue. It does
not authorize promotion. Nothing reaches the catalog without a human, because
an extraction error here becomes a dosing error downstream.

Client-side OCR, if added, exists only to show the user what was read
("Vitamin D3, 5000 IU — look right?") and to catch an unreadable photo before
submission. **The photo is the record.** Client-extracted text is never
persisted as product data.

**Review surface:** start with Supabase Studio plus a `submission_review`
SQL view and signed-URL helper. Zero build, works today, and at current
volume (0 rows) a bespoke admin is speculative. Graduate to a small Next.js
admin on Vercel when queue depth justifies it — not before.

---

## 6. Notification

`promoted_catalog_version` is what makes the notification provable rather
than guessed: the user is told the product is available only once it is
actually in a shipped catalog version their app can resolve.

Deliver **in-app on next open**, not push. Submission status is not urgent,
push means a new permission prompt and FCM/APNs setup, and the research
finding driving the current roadmap is that notification fatigue is the top
complaint in this category. A quiet in-app "the product you submitted is now
in the catalog" is sufficient and costs nothing.

---

## 7. Multi-source ingestion

The architectural point: **do not build a second pipeline.** Every source
becomes a normalizer emitting `manual_labels/*.json`, and the existing
classification, scoring, interaction matching, export, and bundling run
unchanged. One contract, N adapters.

Each adapter must populate `manual_product_provenance` honestly —
`source_url`, `label_verified_at`, `review_status`, `reviewer`. Provenance is
what lets a later audit distinguish a verified manufacturer PDF from a
best-effort scrape.

Ordered by defensibility and effort:

1. **User submissions** — the flow in this document, with explicit consent
   for private processing and human verification before promotion.
2. **Manufacturer PDFs or feeds** — use only official materials whose reuse
   terms permit ingestion. The same VLM normalizer can process label tables,
   but the source document and review decision remain provenance.
3. **Open Food Facts evaluation** — barcode-indexed and available by API, but
   not CC0. Its database is ODbL, individual contents use the Database
   Contents License, and images are CC BY-SA. Measure supplement coverage and
   complete a license/attribution/share-alike review before combining its data
   or images with the PharmaGuide catalog:
   https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/license-be-on-the-legal-side/
4. **Brand/retailer pages** — schema.org markup does not itself grant reuse
   rights. Respect robots.txt and site terms, and prefer an authorized feed,
   API, or written permission over scraping.

Identity resolution against the existing catalog must key on the same
`source_path`/UPC discipline the pipeline already uses, never on raw label
text.

---

## 8. Stack rationale

**No new infrastructure.** Supabase (Postgres + Storage + Edge Functions) and
the existing Python pipeline cover this end to end. Adding a queue broker or
microservices would be speculative scaffolding at zero current volume.

- Transport: existing client → Postgres → Storage, draft/upload/finalize.
- Trigger: Edge Function on status change.
- Extraction: VLM job writing `extraction_json`.
- Review: Studio + SQL views now; Next.js admin later if justified.
- Promotion: the existing `release_full.sh` train. Submissions become
  `manual_labels` entries; nothing downstream changes.

Scaling levers if volume arrives: `pg_cron` for batch extraction,
`pgmq` for retries. Both are Supabase-native and additive — neither needs to
exist on day one.

---

## 9. Phasing

1. **Unblock** — deploy the existing tables/RPC/private-bucket/RLS migration,
   deploy `review-label-mismatch`, configure reviewer IDs, and run a real
   authenticated submission canary. No client code change is required.
2. **Widen** — `kind = 'missing_product'`, submission entry point from the
   failed-scan queue, three-shot guided capture reusing the existing sheet.
3. **Extract** — VLM job, `needs_review` queue, Studio review view.
4. **Close the loop** — approved → `manual_labels` → release train →
   `promoted` → in-app notification.
5. **Widen sources** — Open Food Facts adapter, then PDFs.

Phase 1 is small and strictly repairs a shipping bug. It is worth doing on
its own even if everything after it is deferred.

---

## 10. Open questions

1. **Does the mismatch entry point stay live during Phase 1?** It currently
   fails for every user. Either ship the migration promptly or hide the entry
   point until it lands.
2. **Retention window for photos** — 90 days post-decision is proposed; needs
   a privacy call since these are user-supplied images.
3. **Anonymous submissions?** Current RLS requires an authenticated user, and
   `user_id` is needed to notify. That means unsigned users cannot contribute
   — acceptable, but it is a deliberate trade-off against the app's
   otherwise-offline-first stance.
4. **Open Food Facts licensing and trust** — before any adapter work, decide
   whether ODbL/share-alike obligations fit the catalog architecture and
   measure actual supplement coverage. If adopted, imported records remain
   drafts requiring human review; crowd-sourced identity is not auto-trusted.
