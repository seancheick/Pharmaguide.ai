import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('clinical_risk_vocab.json drift contract', () {
    final file = File('assets/data/clinical_risk_vocab.json');

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
      final entries =
          (decoded['clinical_risks'] as List).cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(ids,
          equals({'critical', 'high', 'moderate', 'dose_dependent', 'low'}));
    });

    test('full display contract populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['clinical_risks'] as List).cast<Map<String, dynamic>>();

      const required = {
        'id', 'name', 'short_label', 'tone',
        'ui_color', 'ui_icon', 'action', 'notes',
      };

      for (final r in entries) {
        for (final f in required) {
          expect(r[f], isA<String>(), reason: '${r['id']}: $f not string');
          expect((r[f] as String).trim().isNotEmpty, isTrue,
              reason: '${r['id']}: $f empty');
        }
        expect(r['severity_weight'], isA<int>());
      }
    });

    test('display enums valid', () {
      const tones = {'positive', 'neutral', 'info', 'warning', 'danger'};
      const colors = {'green', 'blue', 'gray', 'yellow', 'orange', 'red'};
      const icons = {'check', 'info', 'warning', 'alert', 'block'};

      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['clinical_risks'] as List).cast<Map<String, dynamic>>();

      for (final r in entries) {
        expect(tones.contains(r['tone']), isTrue);
        expect(colors.contains(r['ui_color']), isTrue);
        expect(icons.contains(r['ui_icon']), isTrue);
      }
    });
  });
}
