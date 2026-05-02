import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('confidence_tier_vocab.json drift contract', () {
    final file = File('assets/data/confidence_tier_vocab.json');

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
      final entries = (decoded['confidence_tiers'] as List)
          .cast<Map<String, dynamic>>();
      expect(entries.map((e) => e['id'] as String).toSet(),
          equals({'high', 'medium', 'low'}));
    });

    test('full display contract populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['confidence_tiers'] as List)
          .cast<Map<String, dynamic>>();
      const required = {
        'id', 'name', 'short_label', 'tone',
        'ui_color', 'ui_icon', 'action', 'notes',
      };
      for (final c in entries) {
        for (final f in required) {
          expect(c[f], isA<String>(), reason: '${c['id']}: $f');
          expect((c[f] as String).trim().isNotEmpty, isTrue);
        }
      }
    });
  });
}
