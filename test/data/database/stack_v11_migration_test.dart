// v11 migration: user-reported start date + per-item reminder.
//
// Adding a column is the kind of change that looks trivial and silently
// destroys data if the migration is wrong, so this exercises the real upgrade
// path against a real pre-v11 file rather than a fresh createAll().

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pg-v11-migration');
    dbPath = '${tempDir.path}/user_data.db';
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// A v10-shaped `user_stacks_local` holding one row, with no v11 columns.
  void seedV10Database() {
    final legacy = sqlite3.open(dbPath);
    try {
      legacy.execute('''
        CREATE TABLE user_stacks_local (
          id TEXT NOT NULL PRIMARY KEY,
          type TEXT NOT NULL DEFAULT 'supplement',
          name TEXT NOT NULL,
          dsld_id TEXT,
          rxcui TEXT,
          ingredient_keys TEXT,
          drug_classes TEXT,
          generic_rxcui TEXT,
          ingredient_rxcuis TEXT,
          dosage TEXT,
          frequency TEXT,
          added_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          client_updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          deleted_at INTEGER,
          synced_at INTEGER,
          sync_blocked_at INTEGER
        );
      ''');
      // beforeOpen builds hot-path indexes across these tables on every open,
      // so a realistic v10 file has to contain them.
      legacy.execute('''
        CREATE TABLE user_scan_history (dsld_id TEXT);
        CREATE TABLE user_favorites (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          dsld_id TEXT NOT NULL,
          added_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        );
        CREATE TABLE health_history_events (
          sequence INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          id TEXT NOT NULL UNIQUE,
          event_type TEXT NOT NULL,
          source TEXT NOT NULL,
          subject_type TEXT NOT NULL,
          subject_id TEXT,
          state TEXT NOT NULL DEFAULT 'occurred',
          title TEXT NOT NULL,
          summary TEXT,
          effective_at INTEGER NOT NULL,
          recorded_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          previous_value_json TEXT,
          current_value_json TEXT,
          metadata_json TEXT,
          payload_schema_version INTEGER NOT NULL DEFAULT 1,
          reminder_at INTEGER,
          dedupe_key TEXT
        );
      ''');
      legacy.execute(
        "INSERT INTO user_stacks_local (id, type, name, dosage, added_at, "
        "client_updated_at) VALUES "
        "('entry-1', 'medication', 'Metformin', '500 mg', 1600000000, "
        "1600000000)",
      );
      legacy.execute('PRAGMA user_version = 10;');
    } finally {
      legacy.dispose();
    }
  }

  test('upgrading from v10 adds both columns and preserves the row', () async {
    seedV10Database();

    final db = UserDatabase.open(dbPath);
    addTearDown(db.close);

    final rows = await db.getActiveStack();
    expect(rows, hasLength(1), reason: 'the pre-existing row must survive');

    final row = rows.single;
    expect(row.name, 'Metformin');
    expect(row.dosage, '500 mg', reason: 'existing columns must be untouched');
    // Absent rather than fabricated: the app was never told a start date.
    expect(row.startedAt, isNull);
    expect(row.reminderMinutes, isNull);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });

  test('the upgraded database accepts writes to the new columns', () async {
    seedV10Database();

    final db = UserDatabase.open(dbPath);
    addTearDown(db.close);

    final startedAt = DateTime.utc(2019, 5, 1);
    await db.customStatement(
      'UPDATE user_stacks_local SET started_at = ?, reminder_minutes = ? '
      'WHERE id = ?',
      [startedAt.millisecondsSinceEpoch ~/ 1000, 480, 'entry-1'],
    );

    final row = (await db.getActiveStack()).single;
    expect(row.startedAt?.toUtc(), startedAt);
    expect(row.reminderMinutes, 480);
  });

  test('re-opening an already-migrated database is a no-op', () async {
    seedV10Database();

    final first = UserDatabase.open(dbPath);
    await first.getActiveStack();
    await first.close();

    // A second open must not attempt to re-add the columns.
    final second = UserDatabase.open(dbPath);
    addTearDown(second.close);
    expect(await second.getActiveStack(), hasLength(1));
  });
}
