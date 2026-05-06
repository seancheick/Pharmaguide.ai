import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('banned_status_vocab.json drift contract', () {
    final file = File('assets/data/banned_status_vocab.json');

    test('asset bundle present', () {
      expect(file.existsSync(), isTrue);
    });

    test('schema lock + 4 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;

      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 4);
      expect((md['status'] as String).contains('LOCKED'), isTrue);
    });

    test('canonical 4 IDs present', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['banned_statuses'] as List)
          .cast<Map<String, dynamic>>();
      final ids = entries.map((e) => e['id'] as String).toSet();

      expect(ids, equals({'banned', 'recalled', 'high_risk', 'watchlist'}));
    });

    test('every entry has full display contract populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['banned_statuses'] as List)
          .cast<Map<String, dynamic>>();

      const required = {
        'id',
        'name',
        'short_label',
        'tone',
        'ui_color',
        'ui_icon',
        'action',
        'notes',
        'regulatory_basis',
      };

      for (final s in entries) {
        for (final f in required) {
          expect(s[f], isA<String>(), reason: '${s['id']}: $f not string');
          expect(
            (s[f] as String).trim().isNotEmpty,
            isTrue,
            reason: '${s['id']}: $f empty',
          );
        }
      }
    });

    test('display enums valid', () {
      const tones = {'positive', 'neutral', 'info', 'warning', 'danger'};
      const colors = {'green', 'blue', 'gray', 'yellow', 'orange', 'red'};
      const icons = {'check', 'info', 'warning', 'alert', 'block'};

      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['banned_statuses'] as List)
          .cast<Map<String, dynamic>>();

      for (final s in entries) {
        expect(tones.contains(s['tone']), isTrue, reason: '${s['id']} tone');
        expect(
          colors.contains(s['ui_color']),
          isTrue,
          reason: '${s['id']} color',
        );
        expect(icons.contains(s['ui_icon']), isTrue, reason: '${s['id']} icon');
      }
    });
  });
}
