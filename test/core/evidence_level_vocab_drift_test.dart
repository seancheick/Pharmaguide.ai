import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evidence_level_vocab.json drift contract', () {
    final file = File('assets/data/evidence_level_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 6 entries', () {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 6);
      expect((md['status'] as String).contains('LOCKED'), isTrue);
    });

    test('canonical clinical-study design IDs present', () {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final entries = (decoded['evidence_levels'] as List)
          .cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids,
        equals({
          'product-human',
          'branded-rct',
          'ingredient-human',
          'strain-clinical',
          'preclinical',
          'reference',
        }),
      );
    });

    test('every entry has required fields populated', () {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final entries = (decoded['evidence_levels'] as List)
          .cast<Map<String, dynamic>>();

      for (final entry in entries) {
        for (final field in {'id', 'name', 'notes'}) {
          expect(entry[field], isA<String>(), reason: '${entry['id']}: $field');
          expect((entry[field] as String).trim().isNotEmpty, isTrue);
        }
        expect(entry['multiplier'], isA<num>());
        expect(entry['tier'], isA<int>());
        expect((entry['notes'] as String).length, lessThanOrEqualTo(200));
      }
    });
  });
}
