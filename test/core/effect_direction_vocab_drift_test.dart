import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('effect_direction_vocab.json drift contract', () {
    final file = File('assets/data/effect_direction_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 5 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 5);
    });

    test('canonical 5 IDs present', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['effect_directions'] as List)
          .cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids,
        equals({
          'positive_strong',
          'positive_weak',
          'mixed',
          'null',
          'negative',
        }),
      );
    });

    test('all entries have required fields and valid multipliers', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['effect_directions'] as List)
          .cast<Map<String, dynamic>>();

      for (final e in entries) {
        expect(e['id'], isA<String>());
        expect(e['name'], isA<String>());
        expect(e['notes'], isA<String>());
        expect(e['multiplier'], isA<num>());
        final m = (e['multiplier'] as num).toDouble();
        expect(
          m >= 0.0 && m <= 1.0,
          isTrue,
          reason: '${e['id']} multiplier=$m not in [0,1]',
        );
        expect((e['notes'] as String).length, lessThanOrEqualTo(200));
      }
    });
  });
}
