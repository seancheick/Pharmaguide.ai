import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/products_core_projection.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

void main() {
  test('Drift declares exactly the generated app-core projection', () async {
    final database = CoreDatabase.memory();
    addTearDown(database.close);

    final declared = database.productsCore.$columns
        .map((column) => column.$name)
        .toSet();

    expect(declared, appCoreProjectionColumns);
    expect(declared, isNot(contains('v4_confidence')));
    expect(declared, isNot(contains('score_100_equivalent')));
    expect(declared, isNot(contains('score_ingredient_quality')));
    expect(declared, contains('quality_score_confidence'));
    expect(declared, contains('score_unavailable_reason'));
    expect(declared, contains('route_confidence'));
  });

  test('schema 2.3 confidence alias backfills the canonical column', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pharmaguide-schema-23-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/catalog.db';
    final legacy = raw.sqlite3.open(path);
    try {
      legacy.execute(
        'CREATE TABLE products_core ('
        'dsld_id TEXT PRIMARY KEY, product_name TEXT NOT NULL, upc_sku TEXT, '
        'v4_confidence TEXT, export_version TEXT, exported_at TEXT)',
      );
      legacy.execute(
        "INSERT INTO products_core VALUES "
        "('legacy-23', 'Legacy Product', NULL, 'moderate', '2.3.0', '2026-01-01')",
      );
      legacy.execute(
        "INSERT INTO products_core VALUES "
        "('legacy-blocked', 'Blocked Product', NULL, 'blocked_by_safety_gate', "
        "'2.3.0', '2026-01-01')",
      );
      legacy.execute('PRAGMA user_version = 3');
    } finally {
      legacy.dispose();
    }

    final database = CoreDatabase.open(path);
    addTearDown(database.close);
    final row = await database
        .customSelect(
          'SELECT quality_score_confidence, score_unavailable_reason, '
          "route_confidence FROM products_core WHERE dsld_id = 'legacy-23'",
        )
        .getSingle();

    expect(row.read<String?>('quality_score_confidence'), 'moderate');
    expect(row.read<String?>('score_unavailable_reason'), isNull);
    expect(row.read<String?>('route_confidence'), isNull);

    final blocked = await database
        .customSelect(
          'SELECT quality_score_confidence, score_unavailable_reason '
          'FROM products_core '
          "WHERE dsld_id = 'legacy-blocked'",
        )
        .getSingle();
    expect(blocked.read<String?>('quality_score_confidence'), isNull);
    expect(
      blocked.read<String?>('score_unavailable_reason'),
      'blocked_by_safety_gate',
    );
  });
}
