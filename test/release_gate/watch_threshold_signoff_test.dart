// Release gate: no watch threshold reaches a user without clinical sign-off.
//
// Thresholds are drafted with research and shipped as `proposed` so the
// clinical team can review them in place. Until a reviewer flips one to
// `approved`, the app must behave exactly as if it were not there. This gate
// guards that boundary at the level that matters — the bundled asset the app
// actually reads.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/stack/depletion_checker.dart';

const _validStatuses = {'proposed', 'approved', 'rejected'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('release gate: watch threshold sign-off', () {
    late List<Map<String, dynamic>> entries;

    setUpAll(() async {
      final raw = await rootBundle.loadString(
        'assets/reference_data/medication_depletions.json',
      );
      final data = json.decode(raw) as Map<String, dynamic>;
      entries = (data['depletions'] as List)
          .cast<Map<String, dynamic>>()
          .toList();
    });

    test('every threshold ships with a basis and a review status', () {
      for (final entry in entries) {
        if (!entry.containsKey('watch_threshold_days')) continue;
        final id = entry['id'];
        expect(
          (entry['watch_basis'] as String?)?.trim().isNotEmpty,
          isTrue,
          reason: '$id has a watch threshold with no cited basis',
        );
        expect(
          _validStatuses.contains(entry['watch_review_status']),
          isTrue,
          reason:
              '$id has watch_review_status '
              '${entry['watch_review_status']}, expected one of $_validStatuses',
        );
      }
    });

    test('every threshold is a positive whole number of days', () {
      for (final entry in entries) {
        final raw = entry['watch_threshold_days'];
        if (raw == null) continue;
        expect(
          raw,
          isA<int>(),
          reason: '${entry['id']} threshold must be whole days, got $raw',
        );
        expect(raw as int, greaterThan(0));
      }
    });

    test('an approved threshold records who approved it', () {
      for (final entry in entries) {
        if (entry['watch_review_status'] != 'approved') continue;
        expect(
          (entry['watch_approver'] as String?)?.trim().isNotEmpty,
          isTrue,
          reason:
              '${entry['id']} is approved but names no approver. An approval '
              'with no attributable reviewer is not an approval.',
        );
      }
    });

    test('proposed thresholds are inert in the checker', () {
      // The whole point of the gate: a drafted threshold is invisible until a
      // clinician says yes.
      final checker = DepletionChecker();
      final proposed = entries
          .where((e) => e['watch_review_status'] == 'proposed')
          .map((e) => e['id'])
          .toSet();

      final matches = checker.check(
        medications: const [],
        medicationIdentities: const [
          DepletionMedicationIdentity(name: 'Metformin', rxcui: '860974'),
          DepletionMedicationIdentity(
            name: 'Omeprazole',
            drugClassIds: ['class:acid_suppressants'],
          ),
        ],
        depletionsData: {'depletions': entries},
      );

      for (final match in matches) {
        if (!proposed.contains(match.depletionId)) continue;
        expect(
          match.watchThresholdDays,
          isNull,
          reason:
              '${match.depletionId} is only proposed but surfaced a threshold',
        );
      }
    });
  });
}
