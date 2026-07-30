import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

void main() {
  test('scan lineage columns are nullable for legacy local history', () async {
    final db = UserDatabase.memory();
    addTearDown(db.close);
    final columns = await db
        .customSelect('PRAGMA table_info(user_scan_history)')
        .get();
    final columnNames = columns.map((row) => row.read<String>('name')).toSet();

    expect(columnNames, contains('formula_fingerprint'));
    expect(columnNames, contains('catalog_source_version'));

    await db
        .into(db.scanHistory)
        .insert(const ScanHistoryCompanion(dsldId: Value('legacy-product')));

    final scan = await db.select(db.scanHistory).getSingle();
    expect(scan.formulaFingerprint, isNull);
    expect(scan.catalogSourceVersion, isNull);
  });

  test('scan lineage values round-trip in local history', () async {
    final db = UserDatabase.memory();
    addTearDown(db.close);
    await db
        .into(db.scanHistory)
        .insert(
          const ScanHistoryCompanion(
            dsldId: Value('versioned-product'),
            formulaFingerprint: Value(
              '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
            ),
            catalogSourceVersion: Value('2026.07.19.215257'),
          ),
        );

    final scan = await db.select(db.scanHistory).getSingle();
    expect(
      scan.formulaFingerprint,
      '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
    );
    expect(scan.catalogSourceVersion, '2026.07.19.215257');
  });

  test('schema v7 migrates existing scans with nullable lineage', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'pharmaguide-scan-lineage-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final dbPath = '${tempDir.path}/user_data.db';
    final legacy = raw.sqlite3.open(dbPath);
    try {
      legacy.execute('''
        CREATE TABLE user_scan_history (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          dsld_id TEXT NOT NULL,
          upc_sku TEXT,
          product_name TEXT,
          scanned_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        );
      ''');
      legacy.execute('''
        INSERT INTO user_scan_history (dsld_id, product_name)
        VALUES ('legacy-product', 'Legacy bottle');
      ''');
      legacy.execute('''
        CREATE TABLE user_stacks_local (
          dsld_id TEXT,
          deleted_at INTEGER,
          added_at INTEGER
        );
      ''');
      legacy.execute('''
        CREATE TABLE user_favorites (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          dsld_id TEXT NOT NULL,
          added_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        );
      ''');
      legacy.execute('PRAGMA user_version = 7;');
    } finally {
      legacy.dispose();
    }

    final db = UserDatabase.open(dbPath);
    addTearDown(db.close);
    final existing = await db.select(db.scanHistory).getSingle();

    expect(existing.dsldId, 'legacy-product');
    expect(existing.formulaFingerprint, isNull);
    expect(existing.catalogSourceVersion, isNull);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 10);
    final historyTable = await db
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'health_history_events'",
        )
        .get();
    expect(historyTable, hasLength(1));
  });

  test(
    'recordScanEvent writes lineage returned by recent-scans query',
    () async {
      final db = UserDatabase.memory();
      addTearDown(db.close);

      await db.recordScanEvent(
        dsldId: 'versioned-product',
        formulaFingerprint:
            '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
        catalogSourceVersion: '2026.07.19.215257',
      );

      final recent = await db.getRecentScans();
      expect(recent, hasLength(1));
      expect(
        recent.single.formulaFingerprint,
        '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
      );
      expect(recent.single.catalogSourceVersion, '2026.07.19.215257');
    },
  );
}
