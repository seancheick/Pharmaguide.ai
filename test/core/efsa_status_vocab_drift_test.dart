import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('efsa_status_vocab.json drift contract', () {
    final file = File('assets/data/efsa_status_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 10 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;
      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 10);
    });

    test('canonical 10 IDs', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['efsa_statuses'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        entries.map((e) => e['id'] as String).toSet(),
        equals({
          'approved',
          'approved_with_restrictions',
          'approved_restricted',
          'restricted_eu',
          'banned_eu',
          'not_authorised_eu',
          'contaminant_monitored',
          'under_review',
          'food_ingredient',
          'extraction_solvent',
        }),
      );
    });

    test('all entries have required fields', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['efsa_statuses'] as List)
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
