import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _functionPath = 'supabase/functions/review-product-submissions/index.ts';

void main() {
  late String source;

  setUpAll(() {
    final function = File(_functionPath);
    expect(
      function.existsSync(),
      isTrue,
      reason: 'The unified reviewer boundary must exist.',
    );
    source = function.readAsStringSync().replaceAll('"', "'");
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
      allOf(
        contains("'product_submission_missing_details!'"),
        contains("'product_submission_missing_details_submission_id_fkey('"),
      ),
    );
    expect(photoSigning, greaterThan(readyFilter));
    expect(
      source,
      contains('createSignedUrls(photoPaths, SIGNED_URL_TTL_SECONDS)'),
    );
    expect(source, contains("'product-submission-photos'"));
    expect(source, isNot(contains('createPublicUrl')));
    expect(source, contains('Number(limit) >= 1'));
    expect(source, contains('Number(limit) <= 100'));
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
      'physicalState',
      'productType',
      'servingSizes',
      'servingsPerContainer',
      'statements',
    ]) {
      expect(
        source,
        contains("'$field'"),
        reason:
            'The reviewer and pipeline must pin the same manual-label fields.',
      );
    }
    expect(source, contains('APPROVED_PAYLOAD_MAX_BYTES = 512 * 1024'));
    expect(source, contains('ingredientRows.length > 200'));
    expect(source, contains('servingSizes.length > 20'));
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
}
