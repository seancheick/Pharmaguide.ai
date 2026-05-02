import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('legal_status_vocab.json drift contract', () {
    final file = File('assets/data/legal_status_vocab.json');

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

    test('canonical 10 IDs present', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['legal_statuses'] as List).cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids,
        equals({
          'not_lawful_as_supplement',
          'adulterant',
          'banned_federal',
          'banned_state',
          'controlled_substance',
          'wada_prohibited',
          'restricted',
          'high_risk',
          'contaminant_risk',
          'lawful',
        }),
      );
    });

    test('all entries have required fields', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['legal_statuses'] as List).cast<Map<String, dynamic>>();

      const required = {'id', 'name', 'notes', 'authority', 'implication'};
      const authorities = {'FDA', 'DEA', 'WADA', 'state', 'EU'};

      for (final l in entries) {
        for (final f in required) {
          expect(l[f], isA<String>(), reason: '${l['id']}: $f not string');
          expect((l[f] as String).trim().isNotEmpty, isTrue,
              reason: '${l['id']}: $f empty');
        }
        expect(authorities.contains(l['authority']), isTrue,
            reason: '${l['id']} authority');
        expect((l['notes'] as String).length, lessThanOrEqualTo(200));
      }
    });
  });
}
