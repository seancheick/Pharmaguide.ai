import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('product_type_vocab.json drift contract', () {
    final file = File('assets/data/product_type_vocab.json');

    test('asset file present', () {
      expect(file.existsSync(), isTrue);
    });

    test('declared in Flutter asset bundle', () async {
      final raw = await rootBundle.loadString(
        'assets/data/product_type_vocab.json',
      );
      expect(raw.trim(), startsWith('{'));
    });

    test('schema lock + 20 entries', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final md = decoded['_metadata'] as Map<String, dynamic>;
      expect(md['schema_version'], '1.0.0');
      expect(md['total_entries'], 20);
    });

    test('all entries have required fields and snake_case ids', () {
      final raw = file.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = (decoded['product_types'] as List)
          .cast<Map<String, dynamic>>();

      expect(entries.length, 20);

      const required = {'id', 'name', 'short_name', 'notes'};
      final snakeRe = RegExp(r'^[a-z][a-z0-9_]*$');

      for (final entry in entries) {
        for (final field in required) {
          expect(entry[field], isA<String>(), reason: '${entry['id']}: $field');
          expect((entry[field] as String).trim().isNotEmpty, isTrue);
        }
        expect(snakeRe.hasMatch(entry['id'] as String), isTrue);
      }
    });
  });
}
