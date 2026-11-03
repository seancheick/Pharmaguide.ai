// A failed user_data.db statement must not send its SQL or bound values to
// Sentry: SqliteException.toString writes both. Runs a real failing statement
// through Sentry's own event builder and the real scrub. Values are fictional.

import 'package:drift/drift.dart' show GeneratedDatabase, Table, TableInfo;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const _medicationName = 'Testoprilex (fictional)';
const _rxcui = '0000001';

class _Db extends GeneratedDatabase {
  _Db() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
}

Future<Object> _failedInsert() async {
  final db = _Db();
  addTearDown(db.close);
  await db.customStatement(
    'CREATE TABLE user_stacks_local (id TEXT PRIMARY KEY, name TEXT, rxcui TEXT)',
  );
  const insert = 'INSERT INTO user_stacks_local VALUES (?, ?, ?)';
  await db.customStatement(insert, ['med-1', _medicationName, _rxcui]);
  try {
    await db.customStatement(insert, ['med-1', _medicationName, _rxcui]);
  } on Object catch (error) {
    return error;
  }
  fail('the second insert should have broken the primary key');
}

/// What Sentry would send for [error], after the real scrub.
Future<SentryEvent?> _sentEvent(Object error) async {
  SentryEvent? built;
  SentryEvent? sent;
  await Sentry.init((options) {
    options.dsn = 'https://public@example.ingest.sentry.io/1';
    options.beforeSend = (event, hint) {
      built = event;
      sent = CrashReportingService.scrubEventForTest(event, hint);
      return null;
    };
  });
  addTearDown(Sentry.close);
  await Sentry.captureException(error, stackTrace: StackTrace.current);
  expect(built, isNotNull, reason: 'Sentry never built the event');
  return sent;
}

void _expectClean(String? text) {
  expect(text, isNot(contains(_medicationName)));
  expect(text, isNot(contains(_rxcui)));
  expect(text, isNot(contains('INSERT INTO')));
  expect(text, isNot(contains('parameters:')));
}

void main() {
  test(
    'the failure really does carry the values, or this proves nothing',
    () async {
      final text = (await _failedInsert()).toString();

      expect(text, contains(_medicationName));
      expect(text, contains(_rxcui));
    },
  );

  test('a failed statement reaches Sentry without its SQL or values, and still '
      'says what kind of failure it was', () async {
    final event = await _sentEvent(await _failedInsert());

    final value = event!.exceptions!.single.value;
    _expectClean(value);
    expect(value, contains('UNIQUE constraint failed'));
  });

  test('the same text wrapped in another exception is also removed', () async {
    final failure = await _failedInsert();

    final event = await _sentEvent(Exception('Could not save: $failure'));

    final value = event!.exceptions!.single.value;
    _expectClean(value);
    expect(value, contains('Could not save'));
  });

  test('the same text in an event message is also removed', () async {
    final failure = await _failedInsert();

    final event = CrashReportingService.scrubEventForTest(
      SentryEvent(message: SentryMessage('Could not save: $failure')),
      Hint(),
    );

    _expectClean(event!.message!.formatted);
    expect(event.message!.formatted, contains('Could not save'));
  });

  test('the same text in a breadcrumb message is also removed', () async {
    final failure = await _failedInsert();

    final crumb = CrashReportingService.scrubBreadcrumbForTest(
      Breadcrumb(message: 'Could not save: $failure'),
      Hint(),
    );

    _expectClean(crumb!.message);
    expect(crumb.message, contains('Could not save'));
  });

  test('an error with no SQL in it is left alone', () async {
    final event = await _sentEvent(StateError('nothing to scrub here'));

    expect(event!.exceptions!.single.value, contains('nothing to scrub here'));
  });
}
