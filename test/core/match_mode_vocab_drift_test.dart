import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('match_mode_vocab.json drift contract', () {
    final file = File('assets/data/match_mode_vocab.json');

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
      final entries = (decoded['match_modes'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        entries.map((e) => e['id'] as String).toSet(),
        equals({'active', 'disabled', 'historical'}),
      );
    });

    test('all entries have required fields and bool flag', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['match_modes'] as List)
          .cast<Map<String, dynamic>>();
      for (final m in entries) {
        for (final f in {'id', 'name', 'notes'}) {
          expect(m[f], isA<String>());
          expect((m[f] as String).trim().isNotEmpty, isTrue);
        }
        expect(m['fires_in_scoring'], isA<bool>());
      }
    });
  });
}
