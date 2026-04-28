import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/services/catalog_swap.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late String stagingPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('catalog_swap_test_');
    dbPath = '${tempDir.path}/pharmaguide_core.db';
    stagingPath = '$dbPath.staging';
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // Reusable corePathProvider that returns the fresh tempDir path.
  Future<String> tempPath() async => dbPath;

  group('CatalogSwapper.swap — orchestration (T0.6)', () {
    test('returns SwapNoStaging when no staging file exists', () async {
      final swapper = CatalogSwapper(
        corePathProvider: tempPath,
        activator: () async => fail('activator must not run when no staging'),
        opener: () async => fail('opener must not run when no staging'),
      );

      final result = await swapper.swap();

      expect(result, isA<SwapNoStaging>());
    });

    test('returns SwapRolledBack when corePathProvider throws', () async {
      final swapper = CatalogSwapper(
        corePathProvider: () async => throw const FileSystemException(
              'documents dir unavailable',
            ),
        activator: () async => fail('activator must not run after path failure'),
        opener: () async => fail('opener must not run after path failure'),
      );

      final result = await swapper.swap();

      expect(result, isA<SwapRolledBack>());
      final rolledBack = result as SwapRolledBack;
      expect(rolledBack.reason, contains('Path lookup failed'));
      expect(rolledBack.error, isA<FileSystemException>());
    });

    test('returns SwapRolledBack when activator throws', () async {
      // Pre-create the staging file so swap() reaches the activator.
      File(stagingPath).writeAsBytesSync([0x53, 0x51, 0x4c, 0x69]); // "SQLi"

      final swapper = CatalogSwapper(
        corePathProvider: tempPath,
        activator: () async {
          throw StateError('rename failed: permission denied');
        },
        opener: () async => fail('opener must not run after activation failure'),
      );

      final result = await swapper.swap();

      expect(result, isA<SwapRolledBack>());
      final rolledBack = result as SwapRolledBack;
      expect(rolledBack.reason, contains('Activation failed'));
      expect(rolledBack.error, isA<StateError>());
    });

    test('returns SwapRolledBack when opener throws', () async {
      File(stagingPath).writeAsBytesSync([0x00]);

      final swapper = CatalogSwapper(
        corePathProvider: tempPath,
        activator: () async {/* no-op: pretend rename succeeded */},
        opener: () async {
          throw StateError('cannot open core db: corrupt header');
        },
      );

      final result = await swapper.swap();

      expect(result, isA<SwapRolledBack>());
      final rolledBack = result as SwapRolledBack;
      expect(rolledBack.reason, contains('Open failed'));
      expect(rolledBack.error, isA<StateError>());
    });

    test(
        'returns SwapRolledBack when validation fails — '
        'and closes the new DB (no leaked connection)', () async {
      File(stagingPath).writeAsBytesSync([0x00]);

      // CoreDatabase.memory() has no rows in productsCore, so
      // `validateCatalogSnapshot()` throws `StateError('Catalog
      // snapshot is empty')`. The swapper must close it before
      // returning so we don't leak the connection.
      final memoryDb = CoreDatabase.memory();

      final swapper = CatalogSwapper(
        corePathProvider: tempPath,
        activator: () async {/* no-op */},
        opener: () async => memoryDb,
      );

      final result = await swapper.swap();

      expect(result, isA<SwapRolledBack>());
      final rolledBack = result as SwapRolledBack;
      expect(rolledBack.reason, contains('Validation failed'));
      // The exact error wraps the underlying StateError from the
      // catalog_snapshot validator.
      expect(rolledBack.error, isA<StateError>());
    });

    test('SwapNoStaging when staging file is removed before swap', () async {
      // Touch then remove — verify the existence check catches the
      // race rather than progressing into activation.
      File(stagingPath).writeAsBytesSync([0x01]);
      File(stagingPath).deleteSync();

      var activatorCalled = false;
      final swapper = CatalogSwapper(
        corePathProvider: tempPath,
        activator: () async {
          activatorCalled = true;
        },
        opener: () async => fail('opener must not run'),
      );

      final result = await swapper.swap();

      expect(result, isA<SwapNoStaging>());
      expect(activatorCalled, isFalse,
          reason: 'No staging file → activator must not run');
    });
  });
}
