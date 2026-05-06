import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iqm_category_vocab.json drift contract', () {
    final file = File('assets/data/iqm_category_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 12 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 12);
      expect((md['status'] as String).contains('LOCKED'), isTrue);
    });

    test('canonical 12 IDs present', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['iqm_categories'] as List)
          .cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids,
        equals({
          'amino_acids',
          'antioxidants',
          'enzymes',
          'fatty_acids',
          'fibers',
          'functional_foods',
          'herbs',
          'minerals',
          'other',
          'probiotics',
          'proteins',
          'vitamins',
        }),
      );
    });

    test('every entry has required fields populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['iqm_categories'] as List)
          .cast<Map<String, dynamic>>();

      for (final c in entries) {
        for (final f in {'id', 'name', 'notes'}) {
          expect(c[f], isA<String>(), reason: '${c['id']}: $f not string');
          expect(
            (c[f] as String).trim().isNotEmpty,
            isTrue,
            reason: '${c['id']}: $f empty',
          );
        }
        expect(c['examples'], isA<List<dynamic>>());
        expect((c['examples'] as List<dynamic>).isNotEmpty, isTrue);
        expect((c['notes'] as String).length, lessThanOrEqualTo(200));
      }
    });
  });
}
