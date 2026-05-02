import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('allergen_regulatory_status_vocab.json drift contract', () {
    final file = File('assets/data/allergen_regulatory_status_vocab.json');

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
      final entries = (decoded['allergen_regulatory_statuses'] as List)
          .cast<Map<String, dynamic>>();
      expect(entries.map((e) => e['id'] as String).toSet(),
          equals({'fda_major', 'eu_major', 'eu_allergen'}));
    });

    test('all entries have required fields', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['allergen_regulatory_statuses'] as List)
          .cast<Map<String, dynamic>>();
      const required = {'id', 'name', 'notes', 'authority'};
      const auths = {'FDA', 'EU'};
      for (final i in entries) {
        for (final f in required) {
          expect(i[f], isA<String>());
          expect((i[f] as String).trim().isNotEmpty, isTrue);
        }
        expect(auths.contains(i['authority']), isTrue);
      }
    });
  });
}
