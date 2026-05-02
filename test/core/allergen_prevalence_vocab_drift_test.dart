import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('allergen_prevalence_vocab.json drift contract', () {
    final file = File('assets/data/allergen_prevalence_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 3 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;
      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 3);
    });

    test('canonical 3 IDs', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['allergen_prevalences'] as List)
          .cast<Map<String, dynamic>>();
      expect(entries.map((e) => e['id'] as String).toSet(),
          equals({'high', 'moderate', 'low'}));
    });

    test('full display contract populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['allergen_prevalences'] as List)
          .cast<Map<String, dynamic>>();
      const required = {
        'id', 'name', 'short_label', 'tone',
        'ui_color', 'ui_icon', 'action', 'notes',
      };
      for (final p in entries) {
        for (final f in required) {
          expect(p[f], isA<String>(), reason: '${p['id']}: $f');
          expect((p[f] as String).trim().isNotEmpty, isTrue);
        }
      }
    });
  });
}
