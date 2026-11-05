import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/utils/app_version.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';

void main() {
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
