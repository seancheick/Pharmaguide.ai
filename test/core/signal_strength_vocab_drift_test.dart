import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('signal_strength_vocab.json drift contract', () {
    final file = File('assets/data/signal_strength_vocab.json');

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

    test('canonical 3 IDs present', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['signal_strengths'] as List).cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(ids, equals({'strong', 'moderate', 'weak'}));
    });

    test('full display contract populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries =
          (decoded['signal_strengths'] as List).cast<Map<String, dynamic>>();

      const required = {
        'id', 'name', 'short_label', 'tone',
        'ui_color', 'ui_icon', 'action', 'notes', 'threshold_definition',
      };
      const tones = {'positive', 'neutral', 'info', 'warning', 'danger'};
      const colors = {'green', 'blue', 'gray', 'yellow', 'orange', 'red'};
      const icons = {'check', 'info', 'warning', 'alert', 'block'};

      for (final s in entries) {
        for (final f in required) {
          expect(s[f], isA<String>(), reason: '${s['id']}: $f not string');
          expect((s[f] as String).trim().isNotEmpty, isTrue,
              reason: '${s['id']}: $f empty');
        }
        expect(tones.contains(s['tone']), isTrue);
        expect(colors.contains(s['ui_color']), isTrue);
        expect(icons.contains(s['ui_icon']), isTrue);
        expect((s['notes'] as String).length, lessThanOrEqualTo(200));
      }
    });
  });
}
