import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _functionPath = 'supabase/functions/cleanup-product-submissions/index.ts';
const _storageRemovalPath =
    'supabase/functions/_shared/verified_storage_removal.ts';
const _supabaseConfigPath = 'supabase/config.toml';

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

  test(
    'lets only the secret-authenticated cleanup worker bypass JWT routing',
    () {
      final config = File(_supabaseConfigPath);
      expect(
        config.existsSync(),
        isTrue,
        reason:
            'The scheduler has no user JWT, so the cleanup function must be '
            'explicitly configured for its own constant-time secret boundary.',
      );
      final configSource = config.readAsStringSync();
      expect(configSource, contains('[functions.cleanup-product-submissions]'));
      expect(configSource, contains('verify_jwt = false'));
      expect(
        configSource,
        isNot(contains('[functions.review-product-submissions]')),
      );
      expect(configSource, isNot(contains('[functions.delete-account]')));
    },
  );

  test('removes private objects before deleting database manifests', () {
    final storageDelete = source.indexOf('removeStorageObjectsOrThrow(');
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

    final removalHelper = File(_storageRemovalPath);
    expect(removalHelper.existsSync(), isTrue);
    final helperSource = removalHelper.readAsStringSync();
    expect(helperSource, contains('.remove(requestedPaths)'));
    expect(helperSource, contains('.exists(path)'));
    expect(helperSource, contains('data !== false'));
  });
}
