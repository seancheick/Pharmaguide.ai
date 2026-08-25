import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _functionPath = 'supabase/functions/review-product-submissions/index.ts';
const _queuePath = 'supabase/functions/review-product-submissions/queue.ts';
const _schemaPath = 'supabase/functions/review-product-submissions/schema.ts';

void main() {
  late String source;
  late String queueSource;
  late String schemaSource;

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
      contains(
        "const ACTIONS = new Set(['list', 'record_extraction', 'transition'])",
      ),
    );
    expect(source, contains('rejectUnknownKeys'));
    expect(source, isNot(contains('body.table')));
    expect(source, isNot(contains('body.bucket')));
    expect(source, isNot(contains('body.object_path')));
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
    expect(source, contains("admin.rpc('review_product_submission'"));
    expect(source, contains('canonicalJson'));
    expect(source, contains('sha256Hex'));
    expect(source, contains('p_reviewer_id: reviewerId'));
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
      "admin.rpc('review_product_submission'",
      approvalBranch,
    );
    expect(byteVerification, greaterThan(approvalBranch));
    expect(reviewRpc, greaterThan(byteVerification));
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
    final reviewRpc = source.indexOf("admin.rpc('review_product_submission'");
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
}
