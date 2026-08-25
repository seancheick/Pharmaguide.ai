import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrationPath =
    'supabase/migrations/'
    '20260731144527_product_submission_pipeline_20260730.sql';
const _v2MigrationPath =
    'supabase/migrations/'
    '20260824172752_product_submission_evidence_resolution_v2.sql';
const _resubmissionMigrationPath =
    'supabase/migrations/'
    '20260825181500_product_submission_resubmission_of.sql';
const _reviewV2MigrationPath =
    'supabase/migrations/20260825213000_submission_review_v2.sql';

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
        'where normalized_upc is not null and promoted_at is null '
        'and upload_state = \'ready\'',
      ),
      reason:
          'An abandoned pending manifest and an already-promoted contribution '
          'must not block a fresh correction.',
    );
  });

  test('duplicate-barcode submissions are refused at create, not finalize', () {
    final file = File(
      'supabase/migrations/'
      '20260825172103_reject_duplicate_open_submission_at_create.sql',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'Without the create-time guard a duplicate submission '
          'completes every photo upload and only then dies at finalize, '
          'stranding an orphaned pending row and a retry loop.',
    );
    final sql = file.readAsStringSync().toLowerCase();
    expect(sql, contains('before insert on public.product_submissions'));
    expect(sql, contains("existing.upload_state = 'ready'"));
    expect(sql, contains('existing.promoted_at is null'));
    final replayFix = File(
      'supabase/migrations/'
      '20260825173314_preserve_product_submission_replay.sql',
    ).readAsStringSync().toLowerCase();
    expect(
      replayFix,
      contains('existing.id <> new.id'),
      reason:
          'The create RPC is intentionally idempotent for the same '
          'submission id. The duplicate guard must reject a different '
          'submission for the barcode without rejecting a replay of the '
          'already-committed submission itself.',
    );
    expect(
      sql,
      contains('idx_product_submissions_user_open_upc'),
      reason:
          'The app maps this substring to its actionable conflict copy; '
          'the trigger must speak the same language as the index.',
    );
  });

  test('resubmission lineage is additive, owner-scoped, and fail-closed', () {
    final file = File(_resubmissionMigrationPath);
    expect(file.existsSync(), isTrue);
    final resubmissionSql = _normalized(file.readAsStringSync());

    expect(
      resubmissionSql,
      contains(
        'add column resubmission_of uuid references '
        'public.product_submissions(id) on delete set null',
      ),
    );
    expect(resubmissionSql, contains('p_resubmission_of uuid default null'));
    expect(resubmissionSql, contains('target.user_id = caller_id'));
    expect(resubmissionSql, contains("target.review_status = 'rejected'"));
    for (final code in const [
      'photo_quality',
      'missing_panel',
      'label_unreadable',
      'other',
    ]) {
      expect(resubmissionSql, contains("'$code'"));
    }
    expect(resubmissionSql, contains('target.kind = p_kind'));
    expect(
      resubmissionSql,
      contains(
        'target.normalized_upc is not distinct from normalized_upc_value',
      ),
    );
    expect(
      resubmissionSql,
      contains("raise exception 'invalid resubmission lineage'"),
      reason:
          'Missing ids, another user’s ids, and non-rejected rows must all '
          'fail through the same non-enumerating boundary.',
    );
    expect(
      resubmissionSql,
      contains("raise exception 'resubmission replay conflict'"),
      reason: 'An idempotent replay cannot silently change its parent.',
    );
    expect(
      resubmissionSql,
      contains(
        'revoke all on function public.create_product_submission_v2_internal',
      ),
      reason: 'Only the lineage-enforcing wrapper may remain callable.',
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
        contains("target.review_status = 'approved'"),
        reason: 'A duplicate must point to a reviewed canonical submission.',
      );
      expect(
        sql,
        contains('target.kind = submission.kind'),
        reason: 'A duplicate cannot cross submission kinds.',
      );
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

  test('duplicate provenance cannot prevent an account deletion', () {
    expect(
      sql,
      contains(
        'duplicate_of uuid references public.product_submissions(id) '
        'on delete set null',
      ),
      reason:
          'Deleting one user must not be blocked by another user’s duplicate '
          'reference.',
    );
    expect(
      sql,
      contains("review_status <> 'duplicate' and duplicate_of is null"),
      reason:
          'A historical duplicate may outlive a deleted target, but no other '
          'status may carry a duplicate pointer.',
    );
    expect(sql, contains("or review_status = 'duplicate'"));
  });

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
    expect(
      sql,
      isNot(
        contains(
          'grant select, update, delete on table public.product_submissions '
          'to service_role',
        ),
      ),
      reason:
          'Edge Functions mutate lifecycle state through audited RPCs only.',
    );
    expect(
      sql,
      isNot(
        contains(
          'grant select, insert, update, delete '
          'on table public.product_submission_photos to service_role',
        ),
      ),
      reason:
          'The service role may read photo manifests; it must not rewrite '
          'immutable evidence outside the RPC boundary.',
    );
  });

  test('review v2 makes human identity and match history authoritative', () {
    final file = File(_reviewV2MigrationPath);
    expect(file.existsSync(), isTrue);
    final reviewV2 = _normalized(file.readAsStringSync());

    expect(reviewV2, contains('create table public.product_submission_reviewers'));
    expect(reviewV2, contains('create type public.product_submission_match_outcome'));
    expect(reviewV2, contains('create table public.product_submission_match_checks'));
    expect(
      reviewV2,
      contains('create function public.record_product_submission_match_check'),
    );
    expect(reviewV2, contains('reviewer_id uuid := auth.uid()'));
    expect(reviewV2, contains("canonical_gtin14 ~ '^[0-9]{14}\$'"));
    expect(reviewV2, contains('order by match_check.created_at desc'));
    expect(reviewV2, contains("latest_match.outcome <> 'no_match_verified'"));
    expect(
      reviewV2,
      contains("latest_match.index_built_at < now() - interval '60 days'"),
    );
    expect(
      reviewV2,
      contains(
        'grant execute on function public.review_product_submission',
      ),
    );
    expect(reviewV2, contains('to authenticated'));
    expect(
      reviewV2,
      contains('from public, anon, authenticated, service_role'),
      reason: 'Automation identities must be unable to approve.',
    );
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
        isNot(contains('delete from storage.buckets')),
        reason:
            'Supabase protects Storage tables from direct deletion; empty '
            'legacy buckets must be retired through the Storage API.',
      );
      expect(
        sql,
        isNot(contains('alter table label_mismatch_reports add column kind')),
      );
    },
  );

  group('evidence + resolution v2 migration', () {
    late String v2;

    setUpAll(() {
      final file = File(_v2MigrationPath);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'The v2 contribution migration must remain shipped.',
      );
      v2 = _normalized(file.readAsStringSync());
    });

    test('typed evidence categories replace the slot model', () {
      expect(
        v2,
        contains('create type public.product_submission_evidence_category'),
      );
      for (final category in const [
        "'front_identity'",
        "'supplement_facts'",
        "'ingredient_disclosure'",
        "'directions_warnings'",
        "'barcode'",
        "'lot_expiry'",
      ]) {
        expect(v2, contains(category));
      }
      expect(v2, contains('drop type public.product_submission_photo_slot'));
      expect(v2, contains('primary key (submission_id, photo_id)'));
      expect(v2, contains('unique (submission_id, seq)'));
      expect(v2, contains('unique (submission_id, content_sha256)'));
      expect(
        v2,
        contains(
          "object_path = user_id::text || '/' || submission_id::text || '/' "
          "|| photo_id::text",
        ),
        reason: 'Storage paths derive from photo identity, never client text.',
      );
    });

    test('rebuilt photo evidence stays row-secured', () {
      expect(
        v2,
        contains(
          'alter table public.product_submission_photos '
          'enable row level security',
        ),
      );
      expect(
        v2,
        contains(
          'alter table public.product_submission_photos '
          'force row level security',
        ),
      );
      expect(
        v2,
        contains('create policy "product_submission_photos_select_own"'),
      );
    });

    test('missing-product evidence coverage is category complete', () {
      expect(
        v2,
        contains(
          'create function public.product_submission_has_required_evidence',
        ),
      );
      expect(v2, contains('count(distinct category) = 3'));
      expect(
        v2,
        contains('missing required evidence categories'),
        reason: 'Coverage fails fast at create, before any bytes upload.',
      );
    });

    test('resolution contract is typed, mirrored, and status-scoped', () {
      expect(
        v2,
        contains('create type public.product_submission_resolution_code'),
      );
      for (final code in const [
        "'photo_quality'",
        "'missing_panel'",
        "'label_unreadable'",
        "'not_a_supplement'",
        "'already_in_catalog'",
        "'duplicate_submission'",
        "'other'",
      ]) {
        expect(v2, contains(code));
      }
      expect(v2, contains('add column resolution_code'));
      expect(v2, contains('add column resolution_detail'));
      expect(v2, contains('add column resolved_dsld_id'));
      expect(
        v2,
        contains("resolved_dsld_id ~ '^([0-9]{1,30}|pg_sub_[0-9a-f]{32})"),
        reason: 'Resolved ids must be catalog or PG_SUB identities.',
      );
      expect(v2, contains('rejection resolution code required'));
      expect(v2, contains('resolution not allowed for this transition'));
      expect(v2, contains('product_submissions_resolution_consistent'));
    });

    test('promotion stamps resolution and cascades to duplicates', () {
      expect(
        v2,
        contains('drop function public.mark_product_submission_promoted'),
      );
      expect(v2, contains('p_resolved_dsld_id text'));
      expect(
        v2,
        contains(
          "where duplicate_of = p_submission_id and "
          "review_status = 'duplicate'",
        ),
        reason:
            'Duplicate submitters must not stay at on-the-way forever once '
            'their target ships.',
      );
      expect(
        v2,
        contains(
          'grant execute on function '
          'public.mark_product_submission_promoted( uuid, text, text )',
        ),
      );
    });

    test('push deliveries are durable, service-scoped, and policy-free', () {
      expect(
        v2,
        contains('create table public.product_submission_push_deliveries'),
      );
      expect(
        v2,
        contains('insert into public.product_submission_push_deliveries'),
        reason: 'The review RPC records delivery intent in-transaction.',
      );
      expect(
        v2,
        contains(
          'alter table public.product_submission_push_deliveries '
          'force row level security',
        ),
      );
      expect(
        v2,
        isNot(contains('create policy "product_submission_push_deliveries')),
        reason: 'No client route to the push queue.',
      );
      expect(
        v2,
        contains(
          'grant select, update on table '
          'public.product_submission_push_deliveries to service_role',
        ),
      );
    });

    test('carries no free-text user channels into v2', () {
      expect(v2, isNot(contains('submitter_note')));
      expect(v2, isNot(contains('user_note')));
    });
  });
}
