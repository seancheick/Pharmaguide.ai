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
    expect(source, isNot(contains('autoApprove')));
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
  });
}
