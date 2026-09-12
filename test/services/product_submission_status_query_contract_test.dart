import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/product_submission_service.dart';

void main() {
  test('history shows current evidence with retained front first', () {
    final paths = submissionHistoryPhotoPaths(
      {'id': 's', 'evidence_revision': 2},
      [
        {
          'submission_id': 's',
          'revision': 2,
          'photo_ids': ['front', 'new'],
        },
      ],
      [
        {
          'submission_id': 's',
          'photo_id': 'old',
          'seq': 1,
          'categories': ['supplement_facts'],
          'object_path': 'old',
        },
        {
          'submission_id': 's',
          'photo_id': 'new',
          'seq': 1,
          'categories': ['supplement_facts'],
          'object_path': 'new',
        },
        {
          'submission_id': 'other',
          'photo_id': 'front',
          'seq': 0,
          'categories': ['front_identity'],
          'object_path': 'other',
        },
        {
          'submission_id': 's',
          'photo_id': 'front',
          'seq': 2,
          'categories': ['front_identity'],
          'object_path': 'front',
        },
      ],
    );
    expect(paths, ['front', 'new']);
    expect(submissionHistoryPhotoPaths({'id': 's'}, [], []), isEmpty);
  });
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
