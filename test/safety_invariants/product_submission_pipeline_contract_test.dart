import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrationPath =
    'supabase/migrations/20260730175438_product_submission_pipeline.sql';

String _normalized(String source) => source
    .replaceAll(RegExp(r'--[^\n]*'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

void main() {
  late String sql;

  setUpAll(() {
    final file = File(_migrationPath);
    expect(file.existsSync(), isTrue, reason: 'Migration must remain shipped.');
    sql = _normalized(file.readAsStringSync());
  });

  test('uses one normalized submission spine with typed detail tables', () {
    expect(sql, contains('create type public.product_submission_kind'));
    expect(
      sql,
      contains("create table public.product_submissions ( id uuid primary key"),
    );
    expect(
      sql,
      contains('create table public.product_submission_mismatch_details'),
    );
    expect(
      sql,
      contains('create table public.product_submission_missing_details'),
    );
    expect(sql, contains('create table public.product_submission_photos'));
    expect(sql, isNot(contains('submitter_note')));
    expect(sql, isNot(contains('user_note')));
  });

  test('keeps upload, clinical review, and publication state orthogonal', () {
    expect(sql, contains('create type public.product_submission_upload_state'));
    expect(
      sql,
      contains('create type public.product_submission_review_status'),
    );
    expect(
      sql,
      contains('upload_state public.product_submission_upload_state not null'),
    );
    expect(
      sql,
      contains(
        'review_status public.product_submission_review_status not null',
      ),
    );
    expect(sql, contains('promoted_catalog_version text'));
  });

  test('enforces evidence requirements by submission kind', () {
    expect(
      sql,
      contains(
        "if submission.kind = 'missing_product' and not "
        "public.product_submission_has_required_missing_evidence",
      ),
    );
    expect(sql, contains("photo.photo_slot in ('front', 'supplement_facts')"));
    expect(sql, contains("missing.other_ingredients_not_present or exists"));
    expect(
      sql,
      contains("if submission.kind = 'label_mismatch' and not exists"),
    );
  });

  test('authenticated users can only create and read their own rows', () {
    for (final table in const [
      'product_submissions',
      'product_submission_mismatch_details',
      'product_submission_missing_details',
      'product_submission_photos',
    ]) {
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
      expect(
        sql,
        contains('alter table public.$table force row level security'),
      );
    }
    expect(
      sql,
      contains(
        'create policy "product_submissions_select_own" '
        'on public.product_submissions for select to authenticated '
        'using ((select auth.uid()) = user_id)',
      ),
    );
    expect(
      sql,
      isNot(contains('grant update on table public.product_submissions')),
    );
    expect(
      sql,
      isNot(contains('grant delete on table public.product_submissions')),
    );
  });

  test('finalization is owner scoped, idempotent, and fail closed', () {
    expect(
      sql,
      contains('create or replace function public.finalize_product_submission'),
    );
    expect(sql, contains('security definer set search_path = \'\''));
    expect(sql, contains('caller_id uuid := auth.uid()'));
    expect(sql, contains('and candidate.user_id = caller_id'));
    expect(sql, contains("if current_upload_state = 'ready' then return true"));
    expect(
      sql,
      contains('grant execute on function public.finalize_product_submission'),
    );
    expect(sql, contains("object.metadata->>'size'"));
    expect(sql, contains("object.metadata->>'mimetype'"));
    expect(sql, contains("object.user_metadata->>'content_sha256'"));
    expect(
      sql,
      contains(
        "content_sha256 text not null check "
        "(content_sha256 ~ '^[0-9a-f]{64}\$')",
      ),
      reason: 'Every private object manifest needs an immutable content hash.',
    );
  });

  test('rejects bad scanned identities and altered idempotent replays', () {
    expect(
      sql,
      contains(
        'create or replace function '
        'public.is_valid_product_submission_gtin',
      ),
    );
    expect(
      sql,
      contains("dsld_id text not null check (dsld_id ~ '^[0-9]{1,30}\$')"),
    );
    expect(
      sql,
      contains("if nullif(btrim(coalesce(p_upc, '')), '') is not null and ("),
      reason: 'Optional correction UPCs must be validated when supplied.',
    );
    expect(
      sql,
      contains("raise exception 'submission detail replay conflict'"),
    );
    expect(sql, contains("raise exception 'submission photo replay conflict'"));
    expect(sql, contains("raise exception 'duplicate mismatch category'"));
    expect(
      sql,
      contains("persisted.upload_state not in ('pending', 'ready')"),
      reason:
          'An exact retry after an ambiguous successful finalization must work.',
    );
    expect(
      sql,
      contains(
        'create unique index idx_product_submissions_user_open_upc '
        'on public.product_submissions (user_id, kind, normalized_upc) '
        'where normalized_upc is not null and upload_state = \'ready\'',
      ),
      reason:
          'An abandoned pending manifest cannot block a fresh photo capture.',
    );
  });

  test(
    'review artifacts are versioned, attributable, and never self-approved',
    () {
      expect(
        sql,
        contains('create table public.product_submission_extractions'),
      );
      for (final field in const [
        'recorded_by',
        'schema_version',
        'provider',
        'model',
        'prompt_version',
        'input_image_hashes',
        'draft_payload',
        'field_provenance',
      ]) {
        expect(sql, contains(field));
      }
      expect(
        sql,
        contains('create table public.product_submission_review_events'),
      );
      expect(sql, contains('reviewer_id uuid not null'));
      expect(sql, contains('approved_payload_canonical text not null'));
      expect(
        sql,
        contains("extensions.digest(p_approved_payload_canonical, 'sha256')"),
      );
      expect(
        sql,
        contains(
          'create or replace function '
          'public.record_product_submission_extraction',
        ),
      );
      expect(
        sql,
        contains("raise exception 'extraction image hashes do not match'"),
        reason:
            'An extraction draft must be bound to the exact reviewed photos.',
      );
      expect(
        sql,
        contains(
          'create or replace function '
          'public.export_approved_product_submissions',
        ),
      );
      expect(sql, contains('p_after_approved_at timestamptz'));
      expect(sql, contains('p_after_submission_id uuid'));
      expect(
        sql,
        contains(
          '(approved.approved_at, submission.id) > '
          '(p_after_approved_at, p_after_submission_id)',
        ),
      );
      expect(sql, contains('pg_catalog.pg_advisory_xact_lock'));
      expect(
        sql,
        contains(
          "raise exception 'another approved submission awaits promotion'",
        ),
        reason:
            'Two reviewed corrections for one catalog identity must not race '
            'through a release.',
      );
      expect(sql, contains('from public, anon, authenticated'));
      expect(sql, contains("if p_duplicate_of = p_submission_id then"));
      expect(
        sql,
        contains(
          'revoke all on function '
          'public.product_submission_has_required_missing_evidence',
        ),
      );
      expect(
        sql,
        contains(
          'revoke all on function '
          'public.enforce_product_submission_detail_kind()',
        ),
      );
    },
  );

  test('private storage and retention/account-purge manifests are explicit', () {
    expect(
      sql,
      contains(
        "'product-submission-photos', 'product-submission-photos', false",
      ),
    );
    expect(
      sql,
      contains('create policy "product_submission_objects_insert_own"'),
    );
    expect(
      sql,
      contains(
        'create or replace function public.claim_product_submission_cleanup',
      ),
    );
    expect(
      sql,
      contains(
        'create or replace function public.list_product_submission_objects_for_user',
      ),
    );
    expect(sql, contains("cleanup_claimed_at < now() - interval '15 minutes'"));
    expect(sql, contains('evidence_purged_at timestamptz'));
    expect(
      sql,
      contains('delete from public.product_submission_photos as photo'),
      reason: 'Retention removes private evidence manifests after Storage.',
    );
    expect(
      sql,
      contains('set evidence_purged_at = now(), cleanup_claimed_at = null'),
      reason: 'Final review/publication provenance must outlive its photos.',
    );
    expect(
      sql,
      isNot(
        contains(
          'delete from public.product_submissions where id = any'
          '(p_submission_ids) and upload_state = \'cleaning\'',
        ),
      ),
      reason: 'Cleanup must not erase every claimed submission/audit trail.',
    );
  });

  test('service-only RPCs use database grants, not deprecated JWT helpers', () {
    expect(
      sql,
      isNot(contains('auth.role()')),
      reason:
          'Secret API keys run as the service_role database role but are not '
          'legacy service-role JWTs. EXECUTE grants are the durable boundary.',
    );
    for (final functionName in const [
      'record_product_submission_extraction',
      'review_product_submission',
      'export_approved_product_submissions',
      'mark_product_submission_promoted',
      'claim_product_submission_cleanup',
      'complete_product_submission_cleanup',
      'list_product_submission_objects_for_user',
    ]) {
      expect(
        sql,
        contains('grant execute on function public.$functionName'),
        reason: '$functionName must be explicitly granted to service_role.',
      );
    }
  });

  test(
    'legacy mismatch storage is migrated, then retired from the final model',
    () {
      expect(sql, contains('from public.label_mismatch_reports'));
      expect(sql, contains('from public.label_mismatch_report_photos'));
      expect(sql, contains('drop table public.label_mismatch_report_photos'));
      expect(sql, contains('drop table public.label_mismatch_reports'));
      expect(
        sql,
        contains('pending_products contains unreconciled legacy submissions'),
      );
      expect(sql, contains('drop table public.pending_products'));
      expect(
        sql,
        isNot(contains('alter table label_mismatch_reports add column kind')),
      );
    },
  );
}
