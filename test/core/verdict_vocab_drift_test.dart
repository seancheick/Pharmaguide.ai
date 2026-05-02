import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Drift contract test for the bundled verdict_vocab.json asset.
///
/// This is the cutover safety net for the verdict vocab migration:
/// keeps the vocab JSON and the (still-shipping) hardcoded switch in
/// `lib/core/widgets/verdict_badge.dart` in lockstep until the
/// hardcoded switch is physically removed.
///
/// If this test fails, DO NOT fix the vocab — the pipeline-side asset
/// is the source of truth (gated by
/// `scripts/tests/test_verdict_vocab_contract.py` in the pipeline
/// repo). Update the Dart consumer instead.
///
/// What this test asserts:
///   1. The 6 shipped IDs (SAFE/CAUTION/POOR/BLOCKED/UNSAFE/NUTRITION_ONLY) are present
///   2. NOT_SCORED is intentionally absent (review-queue-only per doc)
///   3. The user-facing `name` for each verdict matches the locked
///      label currently shipped by verdict_badge.dart `labelFor()`
///   4. Display contract fields (tone, ui_color, ui_icon, short_label,
///      action) are populated and non-empty for every entry
void main() {
  group('verdict_vocab.json drift contract', () {
    final file = File('assets/data/verdict_vocab.json');

    test('asset bundle present at expected path', () {
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Bundled verdict vocab missing at ${file.path}. '
            'Pipeline ships the canonical version at '
            'scripts/data/verdict_vocab.json — copy it into Flutter '
            'and re-run.',
      );
    });

    test('schema version matches expected lock', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 6);
      expect((md['status'] as String).contains('LOCKED'), isTrue);
    });

    test('canonical 6 shipped verdict IDs present, NOT_SCORED absent', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['verdicts'] as List)
          .cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids,
        equals({
          'SAFE',
          'CAUTION',
          'POOR',
          'BLOCKED',
          'UNSAFE',
          'NUTRITION_ONLY',
        }),
      );
      expect(
        ids.contains('NOT_SCORED'),
        isFalse,
        reason:
            'NOT_SCORED is intentionally absent — products that fail '
            'to score must divert to the review queue per pipeline '
            'contract (REFERENCE_DATA_LOOKUP_OPPORTUNITIES.md §1).',
      );
    });

    test(
      'vocab labels match verdict_badge.dart labelFor() (no drift during cutover)',
      () {
        // These are the labels currently shipping in
        // lib/core/widgets/verdict_badge.dart `labelFor()`. If this map
        // diverges from the hardcoded switch, the migration drifted.
        // Either update the vocab (after clinician sign-off) or update
        // verdict_badge.dart to consume the vocab.
        const expectedLabels = {
          'SAFE': 'Safe',
          'CAUTION': 'Caution',
          'POOR': 'Poor quality',
          'BLOCKED': 'Do not use',
          'UNSAFE': 'Unsafe',
          'NUTRITION_ONLY': 'Food product — see ingredients',
        };

        final raw = file.readAsStringSync();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final entries = (decoded['verdicts'] as List)
            .cast<Map<String, dynamic>>();
        final byId = {for (final e in entries) e['id'] as String: e};

        for (final entry in expectedLabels.entries) {
          final v = byId[entry.key];
          expect(
            v,
            isNotNull,
            reason: 'verdict ${entry.key} missing from vocab',
          );
          expect(
            v!['name'],
            entry.value,
            reason:
                'verdict ${entry.key} label drift: '
                'vocab=${v['name']} vs locked=${entry.value}',
          );
        }
      },
    );

    test('every entry has the full display contract populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['verdicts'] as List)
          .cast<Map<String, dynamic>>();

      const requiredFields = {
        'id',
        'name',
        'short_label',
        'tone',
        'ui_color',
        'ui_icon',
        'action',
        'notes',
      };

      for (final v in entries) {
        for (final f in requiredFields) {
          expect(
            v[f],
            isA<String>(),
            reason: 'verdict ${v['id']}: $f is not a string',
          );
          expect(
            (v[f] as String).trim().isNotEmpty,
            isTrue,
            reason: 'verdict ${v['id']}: $f is empty',
          );
        }
      }
    });

    test('seed display contract enums are valid', () {
      const allowedTones = {'positive', 'neutral', 'info', 'warning', 'danger'};
      const allowedColors = {
        'green',
        'blue',
        'gray',
        'yellow',
        'orange',
        'red',
      };
      const allowedIcons = {'check', 'info', 'warning', 'alert', 'block'};

      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['verdicts'] as List)
          .cast<Map<String, dynamic>>();

      for (final v in entries) {
        expect(
          allowedTones.contains(v['tone']),
          isTrue,
          reason: '${v['id']} tone=${v['tone']}',
        );
        expect(
          allowedColors.contains(v['ui_color']),
          isTrue,
          reason: '${v['id']} ui_color=${v['ui_color']}',
        );
        expect(
          allowedIcons.contains(v['ui_icon']),
          isTrue,
          reason: '${v['id']} ui_icon=${v['ui_icon']}',
        );
      }
    });
  });
}
