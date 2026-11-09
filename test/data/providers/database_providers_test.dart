import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/utils/app_version.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a healthy user database remains usable across reopen', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('user-db-open-valid-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/user_data.db';
    final first = await openUserDatabase(path);
    try {
      await first.addToStack(
        UserStacksLocalCompanion.insert(id: 'retained', name: 'Test item'),
      );
    } finally {
      await first.close();
    }
    final reopened = await openUserDatabase(path);
    try {
      expect((await reopened.getActiveStack()).single.id, 'retained');
    } finally {
      await reopened.close();
    }
  });
  test(
    'an unreadable user database fails before the opener returns it',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp(
        'user-db-open-invalid-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/user_data.db');
      final damaged = List<int>.filled(512, 7);
      damaged.setRange(0, 16, 'SQLite format 3\u0000'.codeUnits);
      await file.writeAsBytes(damaged, flush: true);
      UserDatabase? returned;
      addTearDown(() async => returned?.close());
      await expectLater(
        openUserDatabase(file.path).then((db) {
          returned = db;
          return db;
        }),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('file is not a database'),
          ),
        ),
      );
      expect(file.readAsBytesSync(), damaged);
    },
  );

  group('interaction database compatibility gate', () {
    test('shared warning reader floor excludes the old release cohort', () {
      expect(
        () => enforceInteractionDatabaseVersionGate(
          minAppVersion: '1.0.1',
          schemaVersion: '4.0.0',
          appVersion: '1.0.0',
        ),
        throwsA(isA<InteractionDatabaseVersionGateException>()),
      );
      enforceInteractionDatabaseVersionGate(
        minAppVersion: '1.0.1',
        schemaVersion: '4.0.0',
        appVersion: kAppVersion,
      );
    });

    test('rejects a database requiring a newer app', () {
      expect(
        () => enforceInteractionDatabaseVersionGate(
          minAppVersion: '2.0.0',
          schemaVersion: '1.0.0',
          appVersion: '1.0.0',
        ),
        throwsA(isA<InteractionDatabaseVersionGateException>()),
      );
    });

    test('rejects unparseable requirements and unsupported schema majors', () {
      expect(
        () => enforceInteractionDatabaseVersionGate(
          minAppVersion: 'future',
          schemaVersion: '1.0.0',
          appVersion: '1.0.0',
        ),
        throwsA(isA<InteractionDatabaseVersionGateException>()),
      );
      expect(
        () => enforceInteractionDatabaseVersionGate(
          minAppVersion: '1.0.0',
          schemaVersion: '5.0.0',
          appVersion: '1.0.0',
        ),
        throwsA(isA<InteractionDatabaseVersionGateException>()),
      );
    });

    test(
      'accepts schemas 1 through approved schema 4 compatible requirements',
      () {
        enforceInteractionDatabaseVersionGate(
          minAppVersion: '1.0.0',
          schemaVersion: '1.2.0',
          appVersion: '1.0.0',
        );
        enforceInteractionDatabaseVersionGate(
          minAppVersion: '1.0.0',
          schemaVersion: '2.0.0',
          appVersion: '1.0.0',
        );
        enforceInteractionDatabaseVersionGate(
          minAppVersion: '1.0.0',
          schemaVersion: '3.0.0',
          appVersion: '1.0.0',
        );
        enforceInteractionDatabaseVersionGate(
          minAppVersion: '1.0.0',
          schemaVersion: '4.0.0',
          appVersion: '1.0.0',
        );
        expect(
          () => enforceInteractionDatabaseVersionGate(
            minAppVersion: '1.0.0',
            schemaVersion: '4.0.0',
            appVersion: '1.0.0',
            maxSupportedSchemaMajor: 3,
          ),
          throwsA(isA<InteractionDatabaseVersionGateException>()),
        );
      },
    );
  });
}
