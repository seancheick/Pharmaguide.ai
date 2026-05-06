import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('score_contribution_tier_vocab.json drift contract', () {
    final file = File('assets/data/score_contribution_tier_vocab.json');

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
      final entries = (decoded['score_contribution_tiers'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        entries.map((e) => e['id'] as String).toSet(),
        equals({'tier_1', 'tier_2', 'tier_3'}),
      );
    });

    test('full display contract + tier_rank populated', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['score_contribution_tiers'] as List)
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
      };
      for (final t in entries) {
        for (final f in required) {
          expect(t[f], isA<String>());
          expect((t[f] as String).trim().isNotEmpty, isTrue);
        }
        expect(t['tier_rank'], isA<int>());
      }
    });
  });
}
