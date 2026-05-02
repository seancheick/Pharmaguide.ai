import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('clinical_indication_vocab.json drift contract', () {
    final file = File('assets/data/clinical_indication_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 22 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 22);
      expect((md['status'] as String).contains('LOCKED'), isTrue);
    });

    test('canonical 22 IDs present', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['clinical_indications'] as List)
          .cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids,
        equals({
          'adaptogen_stress',
          'aging_longevity',
          'anti_inflammatory',
          'antioxidant',
          'cardiovascular',
          'cognitive_neurological',
          'digestive_gut',
          'eye_health',
          'general_herbs',
          'hormonal_endocrine',
          'immune',
          'joint_bone',
          'liver_detox',
          'metabolic_blood_sugar',
          'mineral_supplement',
          'mitochondrial_energy',
          'probiotics',
          'skin_hair_collagen',
          'sleep_mood',
          'sports_performance',
          'urinary_genitourinary',
          'vitamin_supplement',
        }),
      );
    });

    test('every entry has required fields populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['clinical_indications'] as List)
          .cast<Map<String, dynamic>>();

      for (final i in entries) {
        for (final f in {'id', 'name', 'notes'}) {
          expect(i[f], isA<String>(), reason: '${i['id']}: $f not string');
          expect((i[f] as String).trim().isNotEmpty, isTrue,
              reason: '${i['id']}: $f empty');
        }
        expect(i['examples'], isA<List<dynamic>>(),
            reason: '${i['id']}: examples not list');
        expect((i['examples'] as List<dynamic>).isNotEmpty, isTrue,
            reason: '${i['id']}: empty examples');
        expect((i['notes'] as String).length, lessThanOrEqualTo(200),
            reason: '${i['id']}: notes >200 chars');
      }
    });
  });
}
