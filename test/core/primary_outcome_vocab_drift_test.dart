import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('primary_outcome_vocab.json drift contract', () {
    final file = File('assets/data/primary_outcome_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 15 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;
      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 15);
    });

    test('all 15 entries have required fields and snake_case ids', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['primary_outcomes'] as List)
          .cast<Map<String, dynamic>>();

      expect(entries.length, 15);

      const required = {
        'id', 'name', 'legacy_display', 'notes', 'related_user_goal_id',
      };
      final snakeRe = RegExp(r'^[a-z][a-z0-9_]*$');

      for (final p in entries) {
        for (final f in required) {
          expect(p[f], isA<String>(), reason: '${p['id']}: $f');
          expect((p[f] as String).trim().isNotEmpty, isTrue);
        }
        expect(snakeRe.hasMatch(p['id'] as String), isTrue);
        expect((p['notes'] as String).length, lessThanOrEqualTo(200));
      }
    });

    test('legacy_display values are unique within vocab', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['primary_outcomes'] as List)
          .cast<Map<String, dynamic>>();
      final legacy = entries.map((e) => e['legacy_display'] as String).toList();
      expect(legacy.toSet().length, legacy.length,
          reason: 'duplicate legacy_display values');
    });
  });
}
