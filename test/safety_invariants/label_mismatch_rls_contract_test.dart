import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/label_mismatch_report_service.dart';

const _migrationPath =
    'supabase/migrations/20260719_label_mismatch_reports.sql';

const _categories = <String>{
  'product_identity',
  'ingredient_missing',
  'ingredient_extra',
  'amount_or_unit',
  'form_or_parenthetical',
  'serving_size_or_directions',
  'other_ingredients',
  'catalog_version_or_status',
};

const _photoSlots = <String>{'front', 'supplement_facts', 'other_ingredients'};

String _withoutComments(String source) =>
    source.replaceAll(RegExp(r'--[^\n]*(?:\n|$)'), ' ');

String _compact(String source) => _withoutComments(
  source,
).toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

String _tableBody(String sql, String tableName) {
  final match = RegExp(
    'create table public\\.$tableName\\s*\\((.*?)\\);',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(_withoutComments(sql));
  expect(match, isNotNull, reason: 'Missing public.$tableName table.');
  return match!.group(1)!;
}

String _policyStatement(String sql, String policyName, String tableName) {
  final match = RegExp(
    'create policy "$policyName"\\s+on $tableName\\s+(.*?);',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(_withoutComments(sql));
  expect(match, isNotNull, reason: 'Missing $policyName policy on $tableName.');
  return _compact(match!.group(1)!);
}

Set<String> _declaredColumns(String tableBody) {
  const constraintKeywords = <String>{
    'constraint',
    'primary',
    'foreign',
    'unique',
    'check',
  };
  return RegExp(
        r'^\s{2}([a-z][a-z0-9_]*)\s+',
        caseSensitive: false,
        multiLine: true,
      )
      .allMatches(tableBody)
      .map((match) => match.group(1)!.toLowerCase())
      .where((name) => !constraintKeywords.contains(name))
      .toSet();
}

Set<String> _enumValues(String sql, String enumName) {
  final match = RegExp(
    'create type public\\.$enumName as enum\\s*\\((.*?)\\);',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(_withoutComments(sql));
  expect(match, isNotNull, reason: 'Missing public.$enumName enum.');
  return RegExp(
    "'([^']+)'",
  ).allMatches(match!.group(1)!).map((match) => match.group(1)!).toSet();
}

Set<String> _columnGrant(String sql, String tableName, String role) {
  final match = RegExp(
    'grant insert\\s*\\((.*?)\\)\\s*on table public\\.$tableName to $role',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(_withoutComments(sql));
  expect(match, isNotNull, reason: 'Missing INSERT column grant.');
  return match!
      .group(1)!
      .split(',')
      .map((column) => column.trim().toLowerCase())
      .toSet();
}

void main() {
  late String sql;
  late String compact;

  setUpAll(() {
    final migration = File(_migrationPath);
    expect(
      migration.existsSync(),
      isTrue,
      reason: 'Task 17 requires $_migrationPath.',
    );
    sql = migration.readAsStringSync();
    compact = _compact(sql);
  });

  test('uses closed categories and an exact non-health report schema', () {
    expect(_enumValues(sql, 'label_mismatch_category'), _categories);
    expect(_enumValues(sql, 'label_mismatch_report_status'), {
      'submitted',
      'under_review',
      'resolved',
      'dismissed',
    });
    expect(_enumValues(sql, 'label_mismatch_upload_state'), {
      'pending',
      'ready',
      'cleaning',
    });

    final body = _tableBody(sql, 'label_mismatch_reports');
    expect(_declaredColumns(body), {
      'id',
      'user_id',
      'dsld_id',
      'upc',
      'source_record_id',
      'catalog_source_version',
      'formula_fingerprint',
      'mismatch_categories',
      'upload_state',
      'status',
      'submitted_at',
      'reviewed_at',
    });
    expect(
      _compact(body),
      contains('mismatch_categories public.label_mismatch_category[] not null'),
    );
    expect(
      _compact(body),
      contains('cardinality(mismatch_categories) between 1 and 8'),
    );
    expect(_compact(body), contains(r"formula_fingerprint ~ '^[0-9a-f]{64}$'"));

    for (final forbidden in <String>[
      'condition',
      'medication',
      'medical',
      'health',
      'diagnosis',
      'symptom',
      'allerg',
      'prescription',
      'dob',
      'birthdate',
      'fit_score',
      'profile',
      'stack',
      'note',
      'description',
      'details',
      'comment',
      'message',
      'label_text',
      'product_name',
      'brand_name',
    ]) {
      expect(
        RegExp(
          '\\b[a-z0-9_]*$forbidden[a-z0-9_]*\\b',
        ).hasMatch(body.toLowerCase()),
        isFalse,
        reason: 'Report schema contains forbidden field token "$forbidden".',
      );
    }
  });

  test('reports are auth-only, owner-scoped, and ownership is immutable', () {
    expect(
      compact,
      contains(
        'alter table public.label_mismatch_reports enable row level security',
      ),
    );
    expect(
      compact,
      contains(
        'alter table public.label_mismatch_reports force row level security',
      ),
    );
    expect(
      compact,
      contains(
        'for select to authenticated using ((select auth.uid()) = user_id)',
      ),
    );
    expect(
      compact,
      contains(
        'create policy "label_mismatch_reports_insert_own" on public.label_mismatch_reports for insert to authenticated',
      ),
    );
    expect(
      compact,
      contains(
        "and upload_state = 'pending' and status = 'submitted' and reviewed_at is null",
      ),
    );
    expect(
      compact,
      contains(
        'revoke all on table public.label_mismatch_reports from public, anon, authenticated, service_role',
      ),
    );
    expect(
      compact,
      contains(
        'grant select on table public.label_mismatch_reports to authenticated',
      ),
    );
    expect(
      compact,
      contains(
        'grant insert ( id, user_id, dsld_id, upc, source_record_id, catalog_source_version, formula_fingerprint, mismatch_categories ) on table public.label_mismatch_reports to authenticated',
      ),
    );
    expect(
      _columnGrant(sql, 'label_mismatch_reports', 'authenticated'),
      LabelMismatchReportService.reportInsertColumns,
      reason:
          'The database grant must accept every key the production client sends.',
    );
    expect(
      compact,
      isNot(contains('grant insert on table public.label_mismatch_reports')),
    );
    expect(
      compact,
      isNot(
        contains(
          'on public.label_mismatch_reports for update to authenticated',
        ),
      ),
    );
    expect(
      compact,
      isNot(
        contains(
          'on public.label_mismatch_reports for delete to authenticated',
        ),
      ),
    );
    expect(
      compact,
      contains(
        'if new.user_id is distinct from old.user_id then raise exception',
      ),
    );
    expect(
      compact,
      contains('create trigger label_mismatch_reports_immutable_owner'),
    );
    expect(
      compact,
      contains(
        'create or replace function public.finalize_label_mismatch_report( p_report_id uuid ) returns boolean language plpgsql security definer',
      ),
    );
    expect(
      compact,
      contains("if current_upload_state = 'ready' then return true"),
    );
    expect(
      compact,
      contains("if current_upload_state <> 'pending' then return false"),
    );
    expect(
      compact,
      contains("set upload_state = 'ready', submitted_at = now()"),
    );
    expect(
      compact,
      contains(
        'grant execute on function public.finalize_label_mismatch_report(uuid) to authenticated, service_role',
      ),
    );
  });

  test('photo metadata allows only three owner-bound named slots', () {
    expect(_enumValues(sql, 'label_mismatch_photo_slot'), _photoSlots);

    final body = _tableBody(sql, 'label_mismatch_report_photos');
    expect(_declaredColumns(body), {
      'report_id',
      'user_id',
      'photo_slot',
      'object_path',
      'content_type',
      'byte_size',
      'created_at',
    });
    final bodyCompact = _compact(body);
    expect(bodyCompact, contains('primary key (report_id, photo_slot)'));
    expect(
      bodyCompact,
      contains(
        'foreign key (report_id, user_id) references public.label_mismatch_reports(id, user_id)',
      ),
    );
    expect(
      bodyCompact,
      contains(
        "object_path = user_id::text || '/' || report_id::text || '/' || photo_slot::text",
      ),
    );
    expect(bodyCompact, contains('byte_size between 1 and 15728640'));
    expect(bodyCompact, contains('content_type in ('));
    for (final mime in [
      'image/jpeg',
      'image/png',
      'image/heic',
      'image/heif',
      'image/webp',
    ]) {
      expect(bodyCompact, contains("'$mime'"));
    }
    expect(
      compact,
      contains(
        'for insert to authenticated with check ( (select auth.uid()) = user_id and exists ( select 1 from public.label_mismatch_reports as report where report.id = label_mismatch_report_photos.report_id and report.user_id = label_mismatch_report_photos.user_id and report.upload_state = \'pending\' ) )',
      ),
    );
    expect(
      compact,
      contains(
        'create trigger label_mismatch_report_photos_pending_parent after insert on public.label_mismatch_report_photos',
      ),
    );
    expect(
      compact,
      contains(
        "if not found or parent_upload_state <> 'pending' then raise exception 'photo manifest is closed'",
      ),
    );
    expect(
      compact,
      contains(
        'revoke all on function public.enforce_label_mismatch_photo_pending() from public, anon, authenticated',
      ),
    );
  });

  test('private bucket policies scope every client object operation to owner', () {
    expect(
      compact,
      contains(
        'insert into storage.buckets ( id, name, public, file_size_limit, allowed_mime_types )',
      ),
    );
    expect(
      compact,
      contains(
        "values ( 'label-mismatch-report-photos', 'label-mismatch-report-photos', false, 15728640,",
      ),
    );
    expect(
      compact,
      contains(
        'on conflict (id) do update set name = excluded.name, public = false',
      ),
    );

    for (final operation in ['select', 'insert', 'update', 'delete']) {
      final policy = _policyStatement(
        sql,
        'label_mismatch_objects_${operation}_own',
        r'storage\.objects',
      );
      expect(policy, contains('for $operation to authenticated'));
      expect(policy, contains("bucket_id = 'label-mismatch-report-photos'"));
      expect(policy, contains('owner_id = (select auth.uid())::text'));
      expect(
        policy,
        contains("(storage.foldername(name))[1] = (select auth.uid())::text"),
      );
      expect(policy, contains('array_length(storage.foldername(name), 1) = 2'));
      expect(policy, contains('storage.filename(name) in ('));
      for (final slot in _photoSlots) {
        expect(policy, contains("'$slot'"));
      }
    }
    for (final operation in ['insert', 'update', 'delete']) {
      final policy = _policyStatement(
        sql,
        'label_mismatch_objects_${operation}_own',
        r'storage\.objects',
      );
      expect(
        policy,
        contains('from public.label_mismatch_report_photos as photo'),
      );
      expect(policy, contains("and report.upload_state = 'pending'"));
      expect(policy, contains('and photo.object_path = name'));
    }
  });

  test('service-role reviewer access is explicit and client access is narrow', () {
    expect(
      compact,
      contains(
        'grant select, delete, update (status, reviewed_at, upload_state) on table public.label_mismatch_reports to service_role',
      ),
    );
    expect(
      compact,
      contains(
        'create policy "label_mismatch_reports_reviewer_delete_cleaning" on public.label_mismatch_reports for delete to service_role using (upload_state = \'cleaning\')',
      ),
    );
    expect(
      compact,
      contains(
        'grant select on table public.label_mismatch_report_photos to service_role',
      ),
    );
    expect(
      compact,
      contains(
        'grant select on table public.label_mismatch_report_photos to authenticated',
      ),
    );
    expect(
      compact,
      contains(
        'grant insert ( report_id, user_id, photo_slot, object_path, content_type, byte_size ) on table public.label_mismatch_report_photos to authenticated',
      ),
    );
    expect(
      compact,
      isNot(
        contains('grant insert on table public.label_mismatch_report_photos'),
      ),
    );
    expect(
      compact,
      contains('for select to service_role'),
      reason:
          'Reviewer storage reads must use server-held service-role access.',
    );
    expect(compact, isNot(contains(' to anon using')));
    expect(compact, isNot(contains(' to anon with check')));
  });

  test('indexes owner and review paths and cannot mutate catalog data', () {
    for (final index in [
      'idx_label_mismatch_reports_user_submitted',
      'idx_label_mismatch_reports_status_submitted',
      'idx_label_mismatch_reports_review_queue',
      'idx_label_mismatch_reports_review_all',
      'idx_label_mismatch_report_photos_user',
    ]) {
      expect(compact, contains('create index $index'));
    }
    expect(
      compact,
      contains(
        'create unique index idx_label_mismatch_report_photos_object_path',
      ),
    );
    expect(
      compact,
      contains(
        'idx_label_mismatch_reports_review_queue on public.label_mismatch_reports ( upload_state, status, submitted_at desc, id desc )',
      ),
    );
    expect(
      compact,
      contains(
        'idx_label_mismatch_reports_review_all on public.label_mismatch_reports ( upload_state, submitted_at desc, id desc )',
      ),
    );

    expect(
      compact,
      isNot(
        matches(
          RegExp(
            r'\b(?:update|delete from|insert into)\s+public\.(?!label_mismatch_)',
          ),
        ),
      ),
      reason: 'Mismatch reports must never write to catalog/public data.',
    );
    expect(compact, isNot(contains('products_core')));
    expect(compact, isNot(contains('export_manifest')));
    expect(compact, isNot(contains('catalog_releases')));
  });
}
