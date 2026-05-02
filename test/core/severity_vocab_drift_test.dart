import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Drift contract test for the bundled severity_vocab.json asset.
///
/// Cutover safety net: keeps the vocab JSON and the (still-shipping)
/// `Severity` enum in `lib/core/constants/severity.dart` in lockstep
/// until the enum's hardcoded `label`/`color` are migrated to read
/// from the vocab.
///
/// What this test asserts:
///   1. Asset bundled at expected path
///   2. The 6 canonical IDs match the Severity enum names
///   3. User-facing `name` for each severity matches the enum's `label`
///      currently shipped by lib/core/constants/severity.dart
///   4. Display contract fields (tone/ui_color/ui_icon/short_label/action)
///      are populated and within enum
///   5. Legacy `info` ID is absent (renamed to `informational` 2026-04-30)
void main() {
  group('severity_vocab.json drift contract', () {
    final file = File('assets/data/severity_vocab.json');

    test('asset bundle present at expected path', () {
      expect(file.existsSync(), isTrue,
          reason: 'Bundled severity vocab missing at ${file.path}');
    });

    test('schema version + total_entries lock', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      // 1.1.0 added `no_data` as 7th severity per integrity-gate audit
      // (2026-05-02). Flutter Severity enum doesn't yet have a no_data
      // variant; consumer migration PR will add it or map no_data to a
      // neutral display path.
      expect(md['schema_version'], '1.1.0');
      expect(md['total_entries'], 7);
      expect((md['status'] as String).contains('LOCKED'), isTrue);
    });

    test('canonical 7 IDs (incl. no_data tier added v1.1.0)', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['severities'] as List).cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids,
        equals({
          'contraindicated',
          'avoid',
          'caution',
          'monitor',
          'informational',
          'safe',
          'no_data',
        }),
      );
    });

    test('legacy `info` ID is absent post-rename', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['severities'] as List).cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids.contains('info'),
        isFalse,
        reason:
            'Legacy `info` ID was renamed to `informational` 2026-04-30 '
            'across pipeline data + emitters. Including it here would '
            'reintroduce the inconsistency.',
      );
    });

    test(
      'vocab labels match Severity enum labels (no drift during cutover)',
      () {
        // These are the labels currently shipping in
        // lib/core/constants/severity.dart `Severity` enum. If this map
        // diverges from the enum, the migration drifted.
        const expectedLabels = {
          'contraindicated': 'Do not use',
          'avoid': 'Not recommended',
          'caution': 'Use caution',
          'monitor': 'Monitor',
          'informational': 'Informational',
          'safe': 'Safe',
        };

        final raw = file.readAsStringSync();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final entries =
            (decoded['severities'] as List).cast<Map<String, dynamic>>();
        final byId = {for (final e in entries) e['id'] as String: e};

        for (final entry in expectedLabels.entries) {
          final s = byId[entry.key];
          expect(s, isNotNull,
              reason: 'severity ${entry.key} missing from vocab');
          expect(
            s!['name'],
            entry.value,
            reason:
                'severity ${entry.key} label drift: '
                'vocab=${s['name']} vs enum=${entry.value}',
          );
        }
      },
    );

    test('every entry has the full display contract populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['severities'] as List).cast<Map<String, dynamic>>();

      const requiredFields = {
        'id', 'name', 'short_label', 'tone',
        'ui_color', 'ui_icon', 'action', 'notes',
      };

      for (final s in entries) {
        for (final f in requiredFields) {
          expect(s[f], isA<String>(),
              reason: 'severity ${s['id']}: $f is not a string');
          expect((s[f] as String).trim().isNotEmpty, isTrue,
              reason: 'severity ${s['id']}: $f is empty');
        }
      }
    });

    test('seed display contract enums are valid', () {
      const allowedTones = {'positive', 'neutral', 'info', 'warning', 'danger'};
      const allowedColors = {'green', 'blue', 'gray', 'yellow', 'orange', 'red'};
      const allowedIcons = {'check', 'info', 'warning', 'alert', 'block'};

      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['severities'] as List).cast<Map<String, dynamic>>();

      for (final s in entries) {
        expect(allowedTones.contains(s['tone']), isTrue,
            reason: '${s['id']} tone=${s['tone']}');
        expect(allowedColors.contains(s['ui_color']), isTrue,
            reason: '${s['id']} ui_color=${s['ui_color']}');
        expect(allowedIcons.contains(s['ui_icon']), isTrue,
            reason: '${s['id']} ui_icon=${s['ui_icon']}');
      }
    });
  });
}
