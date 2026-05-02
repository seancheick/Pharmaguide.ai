import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Drift contract test for the bundled condition_vocab.json asset.
///
/// Cutover safety net: keeps the vocab in lockstep with the
/// (still-shipping) `conditionLabels` map in
/// `lib/core/constants/schema_ids.dart` until that map is migrated to
/// read from the vocab.
void main() {
  group('condition_vocab.json drift contract', () {
    final file = File('assets/data/condition_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 14 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 14);
      expect((md['status'] as String).contains('LOCKED'), isTrue);
    });

    test('canonical 14 IDs match schema_ids.dart `conditions` list', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['conditions'] as List).cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(
        ids,
        equals({
          'pregnancy',
          'lactation',
          'ttc',
          'surgery_scheduled',
          'hypertension',
          'heart_disease',
          'diabetes',
          'bleeding_disorders',
          'kidney_disease',
          'liver_disease',
          'thyroid_disorder',
          'autoimmune',
          'seizure_disorder',
          'high_cholesterol',
        }),
      );
    });

    test('vocab `name` matches schema_ids.dart `conditionLabels`', () {
      // Locked from lib/core/constants/schema_ids.dart conditionLabels map.
      // If this map drifts from the Dart source, the migration broke.
      const expected = {
        'pregnancy': 'Pregnancy',
        'lactation': 'Breastfeeding',
        'ttc': 'Trying to Conceive',
        'surgery_scheduled': 'Upcoming Surgery',
        'hypertension': 'High Blood Pressure',
        'heart_disease': 'Heart Disease',
        'diabetes': 'Diabetes',
        'bleeding_disorders': 'Bleeding Disorders',
        'kidney_disease': 'Kidney Disease',
        'liver_disease': 'Liver Disease',
        'thyroid_disorder': 'Thyroid Condition',
        'autoimmune': 'Autoimmune Condition',
        'seizure_disorder': 'Epilepsy/Seizures',
        'high_cholesterol': 'High Cholesterol',
      };

      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['conditions'] as List).cast<Map<String, dynamic>>();
      final byId = {for (final e in entries) e['id'] as String: e};

      for (final entry in expected.entries) {
        final c = byId[entry.key];
        expect(c, isNotNull, reason: 'condition ${entry.key} missing');
        expect(c!['name'], entry.value,
            reason: '${entry.key} drift: vocab=${c['name']} dart=${entry.value}');
      }
    });

    test('every entry has required fields populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['conditions'] as List).cast<Map<String, dynamic>>();

      for (final c in entries) {
        for (final f in {'id', 'name', 'notes'}) {
          expect(c[f], isA<String>(), reason: '${c['id']}: $f not string');
          expect((c[f] as String).trim().isNotEmpty, isTrue,
              reason: '${c['id']}: $f empty');
        }
        // notes char limit
        expect((c['notes'] as String).length, lessThanOrEqualTo(200),
            reason: '${c['id']}: notes >200 chars');
      }
    });
  });
}
