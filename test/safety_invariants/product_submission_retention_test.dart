import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _functionPath = 'supabase/functions/cleanup-product-submissions/index.ts';

void main() {
  late String source;

  setUpAll(() {
    final function = File(_functionPath);
    expect(
      function.existsSync(),
      isTrue,
      reason: 'Private submission evidence needs a bounded cleanup worker.',
    );
    source = function.readAsStringSync().replaceAll('"', "'");
  });

  test('requires a service-only cleanup secret and bounded batch', () {
    expect(
      source,
      contains("Deno.env.get('PRODUCT_SUBMISSION_CLEANUP_SECRET')"),
    );
    expect(source, contains("request.headers.get('x-cleanup-secret')"));
    expect(source, contains('CLEANUP_LIMIT = 100'));
    expect(source, contains("'claim_product_submission_cleanup'"));
  });

  test('removes private objects before deleting database manifests', () {
    final storageDelete = source.indexOf('.remove(objectPaths)');
    final databaseDelete = source.indexOf(
      "'complete_product_submission_cleanup'",
    );
    expect(storageDelete, greaterThanOrEqualTo(0));
    expect(databaseDelete, greaterThan(storageDelete));
    expect(source, contains("'product-submission-photos'"));
  });

  test('does not silently delete manifests after a storage failure', () {
    expect(source, contains('failedSubmissionIds'));
    expect(source, contains('completedSubmissionIds'));
    expect(source, contains("event: 'product_submission_cleanup'"));
  });
}
