import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _functionPath = 'supabase/functions/review-product-submissions/index.ts';
const _queuePath = 'supabase/functions/review-product-submissions/queue.ts';
const _schemaPath = 'supabase/functions/review-product-submissions/schema.ts';
const _reviewV2MigrationPath =
    'supabase/migrations/20260825213000_submission_review_v2.sql';
const _reviewV2IndexesMigrationPath =
    'supabase/migrations/20260826001957_submission_review_v2_indexes.sql';
const _reviewerIdAmbiguityFixMigrationPath =
    'supabase/migrations/'
    '20260826100000_fix_review_submission_reviewer_id_ambiguity.sql';

void main() {
  late String source;
  late String queueSource;
  late String schemaSource;
  late String reviewV2Sql;
  late String reviewV2IndexesSql;
  late String reviewerIdAmbiguityFixSql;

  setUpAll(() {
    final function = File(_functionPath);
    expect(
      function.existsSync(),
      isTrue,
      reason: 'The unified reviewer boundary must exist.',
    );
    source = function.readAsStringSync().replaceAll('"', "'");
    final queue = File(_queuePath);
    expect(queue.existsSync(), isTrue, reason: 'The list contract must exist.');
    queueSource = queue.readAsStringSync().replaceAll('"', "'");
    final schema = File(_schemaPath);
    expect(
      schema.existsSync(),
      isTrue,
      reason: 'The deep label schema must exist.',
    );
    schemaSource = schema.readAsStringSync().replaceAll('"', "'");
    final migration = File(_reviewV2MigrationPath);
    expect(
      migration.existsSync(),
      isTrue,
      reason: 'The human-only reviewer boundary must be additive.',
    );
    reviewV2Sql = migration.readAsStringSync().replaceAll('"', "'");
    final indexesMigration = File(_reviewV2IndexesMigrationPath);
    expect(
      indexesMigration.existsSync(),
      isTrue,
      reason: 'Reviewer cleanup and allowlist FKs need covering indexes.',
    );
    reviewV2IndexesSql = indexesMigration.readAsStringSync().replaceAll(
      '"',
      "'",
    );
    final reviewerIdFixMigration = File(_reviewerIdAmbiguityFixMigrationPath);
    expect(
      reviewerIdFixMigration.existsSync(),
      isTrue,
      reason: 'The production reviewer-id ambiguity must stay repaired.',
    );
    reviewerIdAmbiguityFixSql = reviewerIdFixMigration
        .readAsStringSync()
        .replaceAll('"', "'");
  });

  test('authenticates an allowlisted reviewer before service-role access', () {
    final userCheck = source.indexOf('.auth.getUser()');
    final reviewerGate = source.indexOf('PRODUCT_SUBMISSION_REVIEWER_IDS');
    final adminKey = source.indexOf('resolveSupabaseAdminKey()', reviewerGate);

    expect(userCheck, greaterThanOrEqualTo(0));
    expect(reviewerGate, greaterThan(userCheck));
    expect(adminKey, greaterThan(reviewerGate));
    expect(source, contains("json({ error: 'Authentication required' }, 401)"));
    expect(
      source,
      contains("json({ error: 'Reviewer access required' }, 403)"),
    );
  });

  test('accepts only explicit review actions and fields', () {
    expect(
      source,
      allOf(
        contains('const ACTIONS = new Set(['),
        contains("'list'"),
        contains("'record_extraction'"),
        contains("'record_match'"),
        contains("'create_reviewer_image_upload'"),
        contains("'transition'"),
      ),
    );
    expect(source, contains('rejectUnknownKeys'));
    expect(source, isNot(contains('body.table')));
    expect(source, isNot(contains('body.bucket')));
    expect(source, isNot(contains('body.object_path')));
  });

  test('product pictures are rights-bound, byte-verified, and singular', () {
    expect(source, contains("'product-submission-reviewer-images'"));
    expect(source, contains("if (action === 'create_reviewer_image_upload')"));
    expect(source, contains('parseReviewerImageUploadRequest(body)'));
    expect(source, contains('createSignedUploadUrl(objectPath)'));
    expect(source, contains('verifyReviewerImageIntegrity('));
    expect(source, contains('detectReviewerImageContentType(bytes)'));
    expect(source, contains("'product_image_photo_id'"));
    expect(source, contains("'product_image_reviewer_object_id'"));
    expect(source, contains('p_product_image_photo_id: productImagePhotoId'));
    expect(
      source,
      contains(
        'p_product_image_reviewer_object_id: productImageReviewerObjectId',
      ),
    );

    final normalized = reviewV2Sql
        .replaceAll(RegExp(r'--[^\n]*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    expect(
      normalized,
      contains('create type public.product_submission_image_rights'),
    );
    expect(
      normalized,
      contains('create table public.product_submission_reviewer_images'),
    );
    expect(normalized, contains('approved_product_image_photo_id uuid'));
    expect(
      normalized,
      contains('approved_product_image_reviewer_object_id uuid'),
    );
    expect(normalized, contains('num_nonnulls('));
    expect(normalized, contains("'front_identity' = any(photo.categories)"));
    expect(
      normalized,
      contains('product_submission_extractions add column usage jsonb'),
    );
    expect(
      normalized,
      contains('create function public.get_approved_product_submission_image'),
    );
    expect(
      normalized,
      contains(
        'grant execute on function public.get_approved_product_submission_image(uuid) to service_role',
      ),
    );
    final imageExportStart = normalized.indexOf(
      'create function public.get_approved_product_submission_image',
    );
    final imageExportEnd = normalized.indexOf(
      'revoke all on function public.record_product_submission_match_check',
      imageExportStart,
    );
    expect(imageExportStart, greaterThanOrEqualTo(0));
    expect(imageExportEnd, greaterThan(imageExportStart));
    expect(
      normalized.substring(imageExportStart, imageExportEnd),
      isNot(contains('promoted_at is null')),
      reason:
          'A transient image-copy failure must remain retryable after release.',
    );
    final normalizedIndexes = reviewV2IndexesSql
        .replaceAll(RegExp(r'--[^\n]*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    for (final index in const [
      'idx_product_submission_match_checks_reviewer',
      'idx_product_submission_reviewer_images_submission',
      'idx_product_submission_reviewer_images_reviewer',
    ]) {
      expect(normalizedIndexes, contains('create index $index'));
    }
  });

  test('lists ready evidence with short-lived private URLs', () {
    final readyFilter = source.indexOf(".eq('upload_state', 'ready')");
    final photoSigning = source.indexOf('createSignedUrls(');

    expect(readyFilter, greaterThanOrEqualTo(0));
    expect(
      source,
      allOf(
        contains("'product_submission_mismatch_details!'"),
        contains("'product_submission_mismatch_details_submission_id_fkey('"),
      ),
      reason:
          'The detail embed must name its one-to-one foreign key because '
          'the owner integrity constraint creates a second relationship.',
    );
    expect(
      source,
      contains('declared_no_separate_ingredient_panel'),
      reason: 'The reviewer cue moved onto the submission envelope in v2.',
    );
    expect(
      source,
      contains('resolution_code,resolution_detail,resolved_dsld_id'),
      reason: 'Reviewers must see prior resolution state in the queue.',
    );
    expect(
      source,
      isNot(contains('product_submission_missing_details!')),
      reason: 'The dropped other_ingredients_not_present embed would 500.',
    );
    expect(photoSigning, greaterThan(readyFilter));
    expect(
      source,
      contains('createSignedUrls(photoPaths, SIGNED_URL_TTL_SECONDS)'),
    );
    expect(source, contains("'product-submission-photos'"));
    expect(source, isNot(contains('createPublicUrl')));
    expect(queueSource, contains('Number(rawLimit) < 1'));
    expect(queueSource, contains('Number(rawLimit) > 100'));
    expect(source, contains('parseListRequest(body)'));
    expect(source, contains("query.in('review_status', statuses)"));
    expect(source, contains('query.or(cursorFilter(listRequest.after))'));
    expect(source, contains('total_open_count: openCountResult.count ?? 0'));
    expect(source, contains('next_after: nextAfter'));
  });

  test('keeps AI extraction drafts separate from approval', () {
    expect(source, contains("'record_product_submission_extraction'"));
    expect(source, contains("'input_image_hashes'"));
    expect(source, contains("'field_provenance'"));
    expect(source, contains("'prompt_version'"));
    expect(source, contains("'confidence'"));
    expect(source, contains('p_recorded_by: reviewerId'));
    expect(source, isNot(contains('autoApprove')));
    final extractionBranch = source.indexOf(
      "if (action === 'record_extraction')",
    );
    final byteVerification = source.indexOf(
      'verifySubmissionPhotoIntegrity(',
      extractionBranch,
    );
    final extractionRpc = source.indexOf(
      "'record_product_submission_extraction'",
      extractionBranch,
    );
    expect(byteVerification, greaterThan(extractionBranch));
    expect(extractionRpc, greaterThan(byteVerification));
  });

  test('approval is an audited RPC transition with a server hash', () {
    expect(source, contains("userClient.rpc('review_product_submission'"));
    expect(source, contains('canonicalJson'));
    expect(source, contains('sha256Hex'));
    expect(source, isNot(contains('p_reviewer_id: reviewerId')));
    expect(source, contains('p_payload_sha256: payloadHash'));
    expect(source, contains("event: 'product_submission_review_access'"));
    expect(source, isNot(contains('console.log(body')));
    expect(source, isNot(contains('console.log(request')));
    expect(source, contains("APPROVED_SCHEMA_VERSION = 'manual_label_v1'"));
    expect(
      source,
      contains('schemaVersion !== APPROVED_SCHEMA_VERSION'),
      reason: 'A reviewer cannot approve an artifact the pipeline cannot read.',
    );
    expect(source, contains('validateApprovedPayload(body.approved_payload)'));
    for (final field in const [
      'brandName',
      'fullName',
      'ingredientRows',
      'nutritionalInfo',
      'offMarket',
      'otherIngredients',
      'otherIngredientsDisclosure',
      'physicalState',
      'productType',
      'servingSizes',
      'servingsPerContainer',
      'statements',
    ]) {
      expect(
        '$source\n$schemaSource',
        contains("'$field'"),
        reason:
            'The reviewer and pipeline must pin the same manual-label fields.',
      );
    }
    expect(source, contains('APPROVED_PAYLOAD_MAX_BYTES = 512 * 1024'));
    expect(schemaSource, contains('payload.ingredientRows.length > 200'));
    expect(schemaSource, contains('payload.servingSizes.length > 20'));
    expect(schemaSource, contains('validateIngredientRow('));
    expect(schemaSource, contains("'included_on_facts_panel'"));
    expect(schemaSource, isNot(contains("'unverified',")));
    expect(source, contains('.download(objectPath)'));
    expect(source, contains('sha256HexBytes(bytes)'));
    final approvalBranch = source.indexOf("if (toStatus === 'approved')");
    final byteVerification = source.indexOf(
      'verifySubmissionPhotoIntegrity(admin, submissionId)',
      approvalBranch,
    );
    final reviewRpc = source.indexOf(
      "userClient.rpc('review_product_submission'",
      approvalBranch,
    );
    expect(byteVerification, greaterThan(approvalBranch));
    expect(reviewRpc, greaterThan(byteVerification));
  });

  test('records exact match evidence through the authenticated boundary', () {
    expect(source, contains("if (action === 'record_match')"));
    expect(source, contains('parseRecordMatchRequest(body)'));
    expect(source, contains("'record_product_submission_match_check'"));
    expect(source, contains('p_index_built_at: match.indexBuiltAt'));
    expect(source, contains('p_canonical_gtin14: match.canonicalGtin14'));
  });

  test('database derives reviewer identity and denies service-role approval', () {
    final normalized = reviewV2Sql
        .replaceAll(RegExp(r'--[^\n]*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    expect(
      normalized,
      contains('create table public.product_submission_reviewers'),
    );
    expect(
      normalized,
      contains(
        'alter table public.product_submission_reviewers force row level security',
      ),
    );
    expect(
      normalized,
      contains(
        'revoke all on table public.product_submission_reviewers from public, anon, authenticated, service_role',
      ),
    );
    expect(normalized, contains('reviewer_id uuid := auth.uid()'));
    expect(
      normalized,
      contains(
        'from public.product_submission_reviewers as reviewer where reviewer.user_id = reviewer_id',
      ),
    );
    expect(normalized, isNot(contains('p_reviewer_id uuid')));
    expect(
      normalized,
      contains('to authenticated'),
      reason: 'Only a signed-in, allowlisted human can execute review.',
    );
    expect(
      normalized,
      contains('from public, anon, authenticated, service_role'),
    );
    expect(normalized, contains("latest_match.outcome <> 'no_match_verified'"));
    expect(
      normalized,
      contains("latest_match.index_built_at < now() - interval '60 days'"),
    );
  });

  test('approval wrapper uses an unambiguous reviewer identity variable', () {
    final normalized = reviewerIdAmbiguityFixSql
        .replaceAll(RegExp(r'--[^\n]*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();

    expect(
      normalized,
      contains('create or replace function public.review_product_submission'),
    );
    expect(normalized, contains('v_reviewer_id uuid := auth.uid()'));
    expect(
      normalized,
      contains(
        'from public.product_submission_reviewers as reviewer where reviewer.user_id = v_reviewer_id',
      ),
    );
    expect(normalized, contains('and image.reviewer_id = v_reviewer_id'));
    expect(
      normalized,
      contains(
        'public.review_product_submission_human_internal( p_submission_id, v_reviewer_id,',
      ),
    );
    expect(
      normalized,
      isNot(contains('declare reviewer_id uuid := auth.uid()')),
    );
    expect(normalized, isNot(contains('where reviewer.user_id = reviewer_id')));
  });

  test('transition accepts the resolution contract and nothing more', () {
    expect(
      source,
      allOf(
        contains("'resolution_code'"),
        contains("'resolution_detail'"),
        contains("'resolved_dsld_id'"),
      ),
    );
    expect(source, contains('p_resolution_code: resolutionCode'));
    expect(source, contains('p_resolution_detail: resolutionDetail'));
    expect(source, contains('p_resolved_dsld_id: resolvedDsldId'));
    expect(
      source,
      contains('RESOLVED_DSLD_PATTERN'),
      reason: 'Resolved ids must match catalog or PG_SUB identity shapes.',
    );
  });

  test('submission pushes are durable, deferred, and generic', () {
    final reviewRpc = source.indexOf(
      "userClient.rpc('review_product_submission'",
    );
    final drainCall = source.indexOf(
      'drainSubmissionPushDeliveries(admin, submissionId)',
      reviewRpc,
    );
    expect(
      drainCall,
      greaterThan(reviewRpc),
      reason: 'The push drain must run only after the audited transition.',
    );
    expect(
      source,
      contains('EdgeRuntime.waitUntil'),
      reason:
          'A bare floating send can be killed when the worker terminates '
          'after responding.',
    );
    expect(
      source,
      contains("from('product_submission_push_deliveries')"),
      reason: 'Sends must drain the durable in-transaction queue.',
    );
    expect(source, contains('buildSubmissionUpdateMessage('));
    expect(
      source,
      isNot(contains('notification: {')),
      reason:
          'Visible push copy lives only in the shared generic constants, '
          'never inline where payload text could reach it.',
    );
    final fcm = File(
      'supabase/functions/_shared/fcm_v1.ts',
    ).readAsStringSync().replaceAll('"', "'");
    expect(fcm, contains("'Your product submission has an update.'"));
    final copyConstants = fcm
        .split('\n')
        .where(
          (line) =>
              line.contains('SUBMISSION_UPDATE_TITLE') ||
              line.contains('SUBMISSION_UPDATE_BODY'),
        )
        .join('\n');
    expect(
      copyConstants,
      isNot(contains(r'${')),
      reason: 'Visible push copy must be constant, never interpolated.',
    );
  });

  test('photo integrity is keyed by photo identity, not slots', () {
    expect(
      source,
      contains("select('photo_id,object_path,byte_size,content_sha256')"),
    );
    expect(source, contains("order('photo_id', { ascending: true })"));
    expect(source, isNot(contains('photo_slot')));
  });

  test('push drain coalesces backlogs to the latest status per submission', () {
    // Field case: three queued rows (under_review, approved, corrected
    // approved) all delivered together when APNs recovered — an outdated
    // "under review" nudge for an already-approved submission. Only the
    // newest pending row per submission may send; older siblings are
    // discarded, and review_events keeps the full history.
    expect(source, contains('partitionSupersededDeliveries'));
    expect(
      source,
      contains(".in('submission_id', candidateSubmissionIds)"),
      reason: 'Supersession must see each candidate submission whole, not '
          'just the rows that happened to land in the stale window.',
    );
    expect(
      source,
      contains(".delete()"),
    );
    final supersedeBlock = source.substring(
      source.indexOf('product_submission_push_supersede_failed'),
      source.indexOf('const rows = latest;'),
    );
    expect(
      supersedeBlock,
      contains('return;'),
      reason: 'Fail closed: if stale rows cannot be discarded, nothing may '
          'send — a sent newest row would leave an older status as the '
          '"newest pending" for a later drain to replay.',
    );
    final supersedeGrant = File(
      'supabase/migrations/20260826150000_push_queue_supersede_delete.sql',
    );
    expect(
      supersedeGrant.existsSync(),
      isTrue,
      reason: 'Discarding queue rows requires the service-role DELETE grant '
          'the v2 migration deliberately omitted.',
    );
    final supersedeGrantSql = supersedeGrant.readAsStringSync().replaceAll(
      '"',
      "'",
    );
    expect(
      supersedeGrantSql,
      contains(
        'GRANT DELETE ON TABLE public.product_submission_push_deliveries',
      ),
    );
    expect(
      supersedeGrantSql,
      contains('SET last_error = NULL'),
      reason: 'Rows delivered by the pre-coalescing drain must stop '
          'advertising the transport failure that preceded their retry.',
    );
    expect(
      supersedeGrantSql,
      contains('WHERE sent_at IS NOT NULL'),
      reason: 'The historical cleanup touches only delivered rows; pending '
          'failures keep their diagnostic last_error.',
    );
  });

  test('a successful retry clears the failure that preceded it', () {
    expect(
      source,
      contains('last_error: null'),
      reason: 'last_error describes the CURRENT state; a delivered row must '
          'not keep advertising the 401 that delayed it.',
    );
  });
}
