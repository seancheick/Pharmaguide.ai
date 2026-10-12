import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sentry PHARMAGUIDE-26: the UI thread hung for 2 s inside `sqlite3_step`.
/// A file-backed `NativeDatabase` runs every query on the UI isolate; the
/// on-device databases (a 65 MB catalog among them) must run SQLite on a
/// background isolate instead. Physical files, not barrels, are scanned.
void main() {
  const files = [
    'lib/data/database/core_database.dart',
    'lib/data/database/interaction_database.dart',
    'lib/data/database/user_database.dart',
  ];

  for (final path in files) {
    test('$path opens its file on a background isolate', () {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('NativeDatabase(dbFile'),
        isFalse,
        reason: 'NativeDatabase(file) runs SQLite on the UI isolate',
      );
      expect(source, contains('NativeDatabase.createInBackground(dbFile'));
    });
  }
}
