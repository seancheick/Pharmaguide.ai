import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _functionPath = 'supabase/functions/review-label-mismatch/index.ts';

void main() {
  late String source;

  setUpAll(() async {
    source = (await File(_functionPath).readAsString()).replaceAll('"', "'");
  });

  test('authenticates and authorizes reviewer before service-role access', () {
    final userCheck = source.indexOf('.auth.getUser()');
    final reviewerGate = source.indexOf('LABEL_MISMATCH_REVIEWER_IDS');
    final serviceRole = source.indexOf('SUPABASE_SERVICE_ROLE_KEY');

    expect(userCheck, greaterThanOrEqualTo(0));
    expect(reviewerGate, greaterThan(userCheck));
    expect(serviceRole, greaterThan(reviewerGate));
    expect(source, contains("json({ error: 'Authentication required' }, 401)"));
    expect(
      source,
      contains("json({ error: 'Reviewer access required' }, 403)"),
    );
  });

  test('uses short-lived signed photo URLs only after reviewer gate', () {
    expect(
      source,
      contains('createSignedUrls(photoPaths, SIGNED_URL_TTL_SECONDS)'),
    );
    expect(source, isNot(contains('createSignedUrl(photo.object_path')));
    expect(source, isNot(contains('createPublicUrl')));
    expect(source, contains('label-mismatch-report-photos'));
    expect(source, contains("Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')"));
    expect(source, contains('if (photos.length > 0)'));
  });

  test('reviews ready reports only and expires stale pending uploads', () {
    final readyFilter = source.indexOf(".eq('upload_state', 'ready')");
    final photoSigning = source.indexOf('createSignedUrls(');
    expect(readyFilter, greaterThanOrEqualTo(0));
    expect(photoSigning, greaterThan(readyFilter));
    expect(source, contains('PENDING_RETENTION_MILLISECONDS'));
    expect(source, contains('PENDING_CLEANUP_LIMIT = 100'));
    expect(source, contains(".in('upload_state', ['pending', 'cleaning'])"));
    expect(source, contains(".update({ upload_state: 'cleaning' })"));
    expect(source, contains(".eq('upload_state', 'cleaning')"));
    expect(source, contains(".lt('submitted_at', cutoff)"));
    expect(source, contains('.remove(objectPaths)'));
    expect(source, contains("event: 'label_mismatch_pending_cleanup'"));
    expect(
      source,
      contains(
        'Maintenance must never make the ready-only review queue unavailable.',
      ),
    );
  });

  test('response and queries use an explicit non-health allowlist', () {
    const reportFields = [
      'id',
      'dsld_id',
      'upc',
      'source_record_id',
      'catalog_source_version',
      'formula_fingerprint',
      'mismatch_categories',
      'status',
      'submitted_at',
      'reviewed_at',
    ];
    const photoFields = [
      'report_id',
      'photo_slot',
      'object_path',
      'content_type',
      'byte_size',
      'created_at',
    ];
    expect(source, contains(reportFields.join(',')));
    expect(source, contains(photoFields.join(',')));

    for (final forbidden in const [
      'profile',
      'medication',
      'condition',
      'allergy',
      'health_note',
      'label_text',
    ]) {
      expect(source.toLowerCase(), isNot(contains('.from(\'$forbidden')));
    }
  });

  test('emits bounded reviewer audit metadata for every outcome', () {
    expect(source, contains("event: 'label_mismatch_review_access'"));
    expect(source, contains('reviewer_id: reviewerId'));
    expect(source, contains('outcome'));
    expect(source, contains('report_count'));
    expect(source, contains('signed_photo_count'));
    expect(source, isNot(contains('console.log(request')));
    expect(source, isNot(contains('console.log(body')));
  });

  test('normal requests cannot choose tables, buckets, or object paths', () {
    expect(source, contains("if (request.method !== 'POST')"));
    expect(
      source,
      contains(
        "const allowedBodyKeys = new Set(['report_id', 'status', 'cursor', 'limit'])",
      ),
    );
    expect(
      source,
      contains('bodyKeys.every((key) => allowedBodyKeys.has(key))'),
    );
    expect(source, isNot(contains('body.table')));
    expect(source, isNot(contains('body.bucket')));
    expect(source, isNot(contains('body.object_path')));
  });

  test('uses bounded newest-first status and cursor pagination', () {
    expect(source, contains('const allowedStatuses = new Set<ReviewStatus>(['));
    for (final status in const [
      'submitted',
      'under_review',
      'resolved',
      'dismissed',
    ]) {
      expect(source, contains("'$status'"));
    }
    expect(source, contains('limit >= 1 && limit <= 100'));
    expect(source, contains(".order('submitted_at', { ascending: false })"));
    expect(source, contains(".order('id', { ascending: false })"));
    expect(
      source,
      contains("reportQuery = reportQuery.eq('status', body.status)"),
    );
    expect(source, contains('submitted_at.lt.'));
    expect(source, contains('id.lt.'));
    expect(source, contains('next_cursor'));
    expect(source, contains('const submittedAtPattern'));
    expect(source, contains(r'\.\d{1,6}'));
    expect(source, contains('submitted_at: submittedAt'));
    expect(source, isNot(contains('parsedDate.toISOString()')));
  });
}
