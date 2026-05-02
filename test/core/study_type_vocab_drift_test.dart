import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('study_type_vocab.json drift contract', () {
    final file = File('assets/data/study_type_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 7 entries', () {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 7);
      expect((md['status'] as String).contains('LOCKED'), isTrue);
    });

    test('canonical study-type IDs present', () {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final entries = (decoded['study_types'] as List)
          .cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids,
        equals({
          'systematic_review_meta',
          'rct_multiple',
          'rct_single',
          'clinical_strain',
          'observational',
          'animal_study',
          'in_vitro',
        }),
      );
    });

    test('base points match scoring config contract', () {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final entries = (decoded['study_types'] as List)
          .cast<Map<String, dynamic>>();
      final byId = {for (final entry in entries) entry['id']: entry};

      expect(byId['systematic_review_meta']!['base_points'], 6);
      expect(byId['rct_multiple']!['base_points'], 5);
      expect(byId['rct_single']!['base_points'], 4);
      expect(byId['clinical_strain']!['base_points'], 4);
      expect(byId['observational']!['base_points'], 2);
      expect(byId['animal_study']!['base_points'], 2);
      expect(byId['in_vitro']!['base_points'], 1);
    });

    test('every entry has required fields populated', () {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final entries = (decoded['study_types'] as List)
          .cast<Map<String, dynamic>>();

      for (final entry in entries) {
        for (final field in {'id', 'name', 'notes'}) {
          expect(entry[field], isA<String>(), reason: '${entry['id']}: $field');
          expect((entry[field] as String).trim().isNotEmpty, isTrue);
        }
        expect(entry['base_points'], isA<int>());
        expect(entry['tier'], isA<int>());
        expect((entry['notes'] as String).length, lessThanOrEqualTo(200));
      }
    });
  });
}
