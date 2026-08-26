import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('status query names the one-to-one mismatch-detail relationship', () {
    final source = File(
      'lib/services/product_submission_service.dart',
    ).readAsStringSync();

    expect(
      source,
      allOf(
        contains("'product_submission_mismatch_details!'"),
        contains("'product_submission_mismatch_details_submission_id_fkey('"),
      ),
      reason:
          'The owner-integrity foreign key creates a second PostgREST '
          'relationship. An unnamed embed returns HTTP 300 and leaves the '
          'contributions page unable to load.',
    );
  });
}
