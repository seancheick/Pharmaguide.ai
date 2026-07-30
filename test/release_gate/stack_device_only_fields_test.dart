// Release gate: device-only stack fields never reach Supabase.
//
// `user_stacks_local` is partially synced — supplements push name, dsld_id,
// dosage, frequency and timestamps. That makes every NEW column on this table
// a privacy decision, because adding one to the payload is a one-line change
// that no other test would catch.
//
// `started_at` (when someone actually began a medication) and
// `reminder_minutes` (when they take it) are health history, not catalog data.
// They stay on the device.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/user_database.dart';

const _syncSourcePath = 'lib/features/stack/services/stack_sync_queue.dart';

const _deviceOnlyColumns = <String>['started_at', 'reminder_minutes'];

void main() {
  group('release gate: device-only stack fields', () {
    late String syncSource;

    setUpAll(() {
      syncSource = File(_syncSourcePath).readAsStringSync();
    });

    test('the sync payload never mentions a device-only column', () {
      for (final column in _deviceOnlyColumns) {
        expect(
          syncSource.contains("'$column'"),
          isFalse,
          reason:
              '$column appears in $_syncSourcePath. It is device-only health '
              'history and must never be pushed to Supabase.',
        );
      }
    });

    test('the payload stays an explicit allowlist, not a row spread', () {
      // A `...row.toJson()` style spread would silently carry every future
      // column to the server. The allowlist is the whole defence.
      expect(syncSource.contains('...row.toJson()'), isFalse);
      expect(syncSource.contains('row.toJson()'), isFalse);
    });

    test('both columns exist and round-trip locally', () async {
      final database = UserDatabase.memory();
      addTearDown(database.close);

      final startedAt = DateTime.utc(2019, 3, 1);
      await database
          .into(database.userStacksLocal)
          .insert(
            UserStacksLocalCompanion.insert(
              id: 'entry-1',
              name: 'Metformin',
              type: const Value('medication'),
              startedAt: Value(startedAt),
              reminderMinutes: const Value(8 * 60),
            ),
          );

      final row = await (database.select(
        database.userStacksLocal,
      )..where((t) => t.id.equals('entry-1'))).getSingle();

      expect(row.startedAt?.toUtc(), startedAt);
      expect(row.reminderMinutes, 480);
    });

    test('both columns default to null for existing rows', () async {
      // Every row that existed before v11 must read as "not reported" rather
      // than as a fabricated start date.
      final database = UserDatabase.memory();
      addTearDown(database.close);

      await database
          .into(database.userStacksLocal)
          .insert(
            UserStacksLocalCompanion.insert(id: 'entry-2', name: 'Vitamin D'),
          );

      final row = await (database.select(
        database.userStacksLocal,
      )..where((t) => t.id.equals('entry-2'))).getSingle();

      expect(row.startedAt, isNull);
      expect(row.reminderMinutes, isNull);
    });
  });
}
