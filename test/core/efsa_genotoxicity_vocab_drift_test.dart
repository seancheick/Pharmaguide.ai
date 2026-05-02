import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('efsa_genotoxicity_vocab.json drift contract', () {
    final file = File('assets/data/efsa_genotoxicity_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 7 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;
      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 7);
    });

    test('canonical 7 IDs', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['genotoxicity_classifications'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        entries.map((e) => e['id'] as String).toSet(),
        equals({
          'negative',
          'positive',
          'equivocal',
          'insufficient_data',
          'indirect',
          'cannot_be_excluded',
          'under_review',
        }),
      );
    });

    test('all entries have required fields', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['genotoxicity_classifications'] as List)
          .cast<Map<String, dynamic>>();
      for (final i in entries) {
        for (final f in {'id', 'name', 'notes'}) {
          expect(i[f], isA<String>());
          expect((i[f] as String).trim().isNotEmpty, isTrue);
        }
        expect((i['notes'] as String).length, lessThanOrEqualTo(200));
      }
    });
  });
}
