import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ban_context_vocab.json drift contract', () {
    final file = File('assets/data/ban_context_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 5 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 5);
    });

    test('canonical 5 IDs present', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['ban_contexts'] as List)
          .cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids,
        equals({
          'substance',
          'adulterant_in_supplements',
          'contamination_recall',
          'watchlist',
          'export_restricted',
        }),
      );
    });

    test('all entries have required fields', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['ban_contexts'] as List)
          .cast<Map<String, dynamic>>();

      const required = {
        'id',
        'name',
        'notes',
        'when_it_applies',
        'action_recommendation',
      };

      for (final b in entries) {
        for (final f in required) {
          expect(b[f], isA<String>(), reason: '${b['id']}: $f not string');
          expect(
            (b[f] as String).trim().isNotEmpty,
            isTrue,
            reason: '${b['id']}: $f empty',
          );
        }
        expect((b['notes'] as String).length, lessThanOrEqualTo(200));
      }
    });
  });
}
