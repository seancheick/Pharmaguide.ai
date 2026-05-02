import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('manufacturer_trust_tier_vocab.json drift contract', () {
    final file = File('assets/data/manufacturer_trust_tier_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 4 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;
      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 4);
    });

    test('canonical 4 IDs', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['manufacturer_trust_tiers'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        entries.map((e) => e['id'] as String).toSet(),
        equals({'trusted', 'neutral', 'violations_minor', 'violations_critical'}),
      );
    });

    test('full display contract populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['manufacturer_trust_tiers'] as List)
          .cast<Map<String, dynamic>>();
      const required = {
        'id', 'name', 'short_label', 'tone',
        'ui_color', 'ui_icon', 'action', 'notes', 'derivation_rule',
      };
      for (final m in entries) {
        for (final f in required) {
          expect(m[f], isA<String>(), reason: '${m['id']}: $f');
          expect((m[f] as String).trim().isNotEmpty, isTrue);
        }
      }
    });
  });
}
