// A catalog update must never leave the phone worse off than it started.
//
// These run the real SyncService activation and the real openCoreDatabase
// against catalog files on disk, because a no-op activator hides the bugs that
// matter here: the backup being deleted before validation, and a bad update
// silently falling back to the much older bundled catalog.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/services/catalog_swap.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

const _bundled = '2026.01.01.000000';
const _lastGood = '2026.02.01.000000';
const _update = '2026.03.01.000000';

void _buildCatalog(String path, String dbVersion, {bool empty = false}) {
  final db = raw.sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE products_core ('
      'dsld_id TEXT, product_name TEXT, export_version TEXT, '
      'upc_sku TEXT, primary_category TEXT, quality_score_v4_100 REAL, '
      'quality_score_status TEXT, mapped_coverage REAL);',
    );
    if (!empty) {
      db.execute("INSERT INTO products_core (export_version) VALUES ('2.0.0')");
    }
    db.execute(
      'CREATE TABLE export_manifest (key TEXT PRIMARY KEY, value TEXT)',
    );
    db.execute("INSERT INTO export_manifest VALUES ('db_version', ?)", [
      dbVersion,
    ]);
    db.execute(
      "INSERT INTO export_manifest VALUES ('min_app_version', '1.0.0')",
    );
    db.execute(
      "INSERT INTO export_manifest VALUES ('schema_version', '2.5.0')",
    );
    db.execute('PRAGMA user_version = 3');
  } finally {
    db.dispose();
  }
}

String _versionOf(String path) {
  final db = raw.sqlite3.open(path);
  try {
    return db
            .select(
              "SELECT value FROM export_manifest WHERE key = 'db_version'",
            )
            .first['value']
        as String;
  } finally {
    db.dispose();
  }
}

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.dbBytes);

  final Uint8List dbBytes;

  @override
  Future<ByteData> load(String key) async {
    if (key == bundledCoreDatabaseAssetPath) {
      return ByteData.sublistView(dbBytes);
    }
    if (key == bundledCoreDatabaseManifestAssetPath) {
      final bytes = utf8.encode(
        jsonEncode({
          'db_version': _bundled,
          'checksum': 'sha256:${sha256.convert(dbBytes)}',
        }),
      );
      return ByteData.sublistView(Uint8List.fromList(bytes));
    }
    throw StateError('no asset $key');
  }
}

void main() {
  late Directory dir;
  late String dbPath;
  late String stagingPath;
  late String backupPath;
  late _FakeBundle bundle;

  Future<CoreDatabase> open() =>
      openCoreDatabase(documentsDirectory: dir, bundle: bundle);

  CatalogSwapper swapper() {
    final sync = SyncService(appVersion: '1.0.0');
    return CatalogSwapper(
      corePathProvider: () async => dbPath,
      activator: () => sync.activateStagedCoreDbAtPathForTest(dbPath),
      opener: open,
    );
  }

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await CrashReportingService().initialize();
    CrashReportingService().clearBuffersForTest();
    dir = Directory.systemTemp.createTempSync('catalog_rollback_test_');
    dbPath = '${dir.path}/pharmaguide_core.db';
    stagingPath = '$dbPath.staging';
    backupPath = '$dbPath.backup';
    final bundledPath = '${dir.path}/bundled_source.db';
    _buildCatalog(bundledPath, _bundled);
    bundle = _FakeBundle(File(bundledPath).readAsBytesSync());
    File(bundledPath).deleteSync();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('in-session update', () {
    test('a valid update activates and retires the backup', () async {
      _buildCatalog(dbPath, _lastGood);
      _buildCatalog(stagingPath, _update);

      final result = await swapper().swap(expectedVersion: _update);

      expect(result, isA<SwapSuccess>());
      final success = result as SwapSuccess;
      addTearDown(success.newDb.close);
      expect(success.version, _update);
      expect(_versionOf(dbPath), _update);
      expect(File(backupPath).existsSync(), isFalse);
    });

    test('an update that fails validation restores the last good catalog, '
        'not the bundled one', () async {
      _buildCatalog(dbPath, _lastGood);
      _buildCatalog(stagingPath, _update, empty: true);
      final result = await swapper().swap(expectedVersion: _update);

      expect(
        result,
        isA<SwapRolledBack>(),
        reason: 'the user must not be told the catalog updated',
      );
      expect(_versionOf(dbPath), _lastGood);
      expect(File(backupPath).existsSync(), isFalse);
      final rolledBack = result as SwapRolledBack;
      addTearDown(() async => rolledBack.restoredDb?.close());
      expect(rolledBack.restoredVersion, _lastGood);
      expect(
        await rolledBack.restoredDb!.validateCatalogSnapshot(),
        _lastGood,
        reason: 'the app needs a working handle to replace its moved one',
      );
      expect(
        CrashReportingService().recordedErrors.map((e) => e.hint),
        contains('catalog_swap:version_mismatch'),
      );
    });
  });

  test(
    'an activation that throws still hands back a working catalog',
    () async {
      _buildCatalog(dbPath, _lastGood);
      _buildCatalog(stagingPath, _update);

      final result = await CatalogSwapper(
        corePathProvider: () async => dbPath,
        activator: () async {
          File(dbPath).renameSync(backupPath);
          throw const FileSystemException('rename failed');
        },
        opener: open,
      ).swap(expectedVersion: _update);

      expect(result, isA<SwapRolledBack>());
      final rolledBack = result as SwapRolledBack;
      addTearDown(() async => rolledBack.restoredDb?.close());
      expect(rolledBack.restoredVersion, _lastGood);
      expect(_versionOf(dbPath), _lastGood);
    },
  );

  group('a failure after the file moved', () {
    test(
      'a failed open that succeeds on retry still installs the update',
      () async {
        _buildCatalog(dbPath, _lastGood);
        _buildCatalog(stagingPath, _update);
        final old = await open();
        var opens = 0;

        final result = await CatalogSwapper(
          corePathProvider: () async => dbPath,
          activator: () => SyncService(
            appVersion: '1.0.0',
          ).activateStagedCoreDbAtPathForTest(dbPath),
          opener: () {
            if (opens++ == 0) throw const FileSystemException('disk full');
            return open();
          },
        ).swap(expectedVersion: _update);

        expect(result, isA<SwapSuccess>());
        final success = result as SwapSuccess;
        addTearDown(success.newDb.close);
        expect(success.version, _update);
        expect(await success.newDb.validateCatalogSnapshot(), _update);
        await old.close();
      },
    );

    test(
      'a catalog that cannot reopen tells the app its handle is dead',
      () async {
        _buildCatalog(dbPath, _lastGood);
        _buildCatalog(stagingPath, _update);
        final old = await open();

        final result = await CatalogSwapper(
          corePathProvider: () async => dbPath,
          activator: () => SyncService(
            appVersion: '1.0.0',
          ).activateStagedCoreDbAtPathForTest(dbPath),
          opener: () async => throw const FileSystemException('disk full'),
        ).swap(expectedVersion: _update);

        expect(result, isA<SwapRolledBack>());
        final rolledBack = result as SwapRolledBack;
        expect(rolledBack.restoredDb, isNull);
        expect(rolledBack.previousHandleInvalid, isTrue);
        await expectLater(old.validateCatalogSnapshot(), throwsA(anything));
        await old.close();
      },
    );

    test('a failure before anything moved leaves the handle trusted', () async {
      _buildCatalog(dbPath, _lastGood);
      _buildCatalog(stagingPath, _update);

      final result = await CatalogSwapper(
        corePathProvider: () async =>
            throw const FileSystemException('no path'),
        activator: () async => fail('nothing should activate'),
        opener: () async => fail('nothing should open'),
      ).swap(expectedVersion: _update);

      expect((result as SwapRolledBack).previousHandleInvalid, isFalse);
    });

    test('a wrong version that slips past the early check restores the last '
        'good catalog', () async {
      const unexpected = '2026.03.15.000000';
      _buildCatalog(dbPath, _lastGood);
      _buildCatalog(stagingPath, _update);
      final sync = SyncService(appVersion: '1.0.0');

      final result = await CatalogSwapper(
        corePathProvider: () async => dbPath,
        activator: () async {
          // Fault injection: the staged file changes after the early check.
          File(stagingPath).deleteSync();
          _buildCatalog(stagingPath, unexpected);
          await sync.activateStagedCoreDbAtPathForTest(dbPath);
        },
        opener: open,
      ).swap(expectedVersion: _update);

      expect(result, isA<SwapRolledBack>());
      final rolledBack = result as SwapRolledBack;
      addTearDown(() async => rolledBack.restoredDb?.close());
      expect(_versionOf(dbPath), _lastGood);
      expect(rolledBack.restoredVersion, _lastGood);
      expect(File(backupPath).existsSync(), isFalse);
    });

    test('a wrong version that cannot be restored reports a failure, and '
        'hands back no catalog', () async {
      const unexpected = '2026.03.15.000000';
      _buildCatalog(dbPath, _lastGood);
      _buildCatalog(stagingPath, _update);
      final sync = SyncService(appVersion: '1.0.0');
      final directory = File(dbPath).parent.path;
      addTearDown(() => Process.runSync('chmod', ['755', directory]));

      final result = await CatalogSwapper(
        corePathProvider: () async => dbPath,
        activator: () async {
          File(stagingPath).deleteSync();
          _buildCatalog(stagingPath, unexpected);
          await sync.activateStagedCoreDbAtPathForTest(dbPath);
          // Fault injection: the backup can no longer be moved back.
          Process.runSync('chmod', ['555', directory]);
        },
        opener: open,
      ).swap(expectedVersion: _update);

      expect(result, isA<SwapRolledBack>());
      final rolledBack = result as SwapRolledBack;
      expect(rolledBack.restoredDb, isNull);
      expect(rolledBack.previousHandleInvalid, isTrue);
      expect(File(backupPath).existsSync(), isTrue);

      // A later launch must retain the refusal, even once disk access returns.
      Process.runSync('chmod', ['755', directory]);
      final relaunched = await open();
      addTearDown(relaunched.close);
      expect(await relaunched.validateCatalogSnapshot(), _lastGood);
    });

    test(
      'a staged file of the wrong version never replaces the live one',
      () async {
        const unexpected = '2026.03.15.000000';
        _buildCatalog(dbPath, _lastGood);
        _buildCatalog(stagingPath, unexpected);
        final old = await open();
        addTearDown(old.close);

        final result = await swapper().swap(expectedVersion: _update);

        expect(result, isA<SwapRolledBack>());
        final rolledBack = result as SwapRolledBack;
        expect(rolledBack.restoredDb, isNull);
        expect(rolledBack.previousHandleInvalid, isFalse);
        expect(_versionOf(dbPath), _lastGood);
        expect(File(stagingPath).existsSync(), isFalse);
        expect(await old.validateCatalogSnapshot(), _lastGood);
      },
    );
  });

  group('durable catalog activation intent', () {
    test(
      'death before activation keeps the previous verified catalog',
      () async {
        _buildCatalog(dbPath, _lastGood);
        await recordCatalogActivation(
          dbPath: dbPath,
          expectedVersion: _update,
          previousVersion: _lastGood,
        );
        final db = await open();
        addTearDown(db.close);
        expect(await db.validateCatalogSnapshot(), _lastGood);
        expect(File('$dbPath.activation.json').existsSync(), isFalse);
      },
    );

    test(
      'an unexpected live catalog with no backup is never adopted',
      () async {
        _buildCatalog(dbPath, '2026.03.15.000000');
        await recordCatalogActivation(
          dbPath: dbPath,
          expectedVersion: _update,
          previousVersion: _lastGood,
        );
        final db = await open();
        addTearDown(db.close);
        expect(await db.validateCatalogSnapshot(), _bundled);
        expect(File('$dbPath.activation.json').existsSync(), isFalse);
      },
    );

    test(
      'a new attempt cannot overwrite unresolved activation intent',
      () async {
        _buildCatalog(dbPath, _lastGood);
        await recordCatalogActivation(
          dbPath: dbPath,
          expectedVersion: _update,
          previousVersion: _lastGood,
        );
        await expectLater(
          recordCatalogActivation(
            dbPath: dbPath,
            expectedVersion: '2026.04.01.000000',
            previousVersion: _update,
          ),
          throwsStateError,
        );
        final recorded =
            jsonDecode(await File('$dbPath.activation.json').readAsString())
                as Map;
        expect(recorded['expected'], _update);
      },
    );
  });

  group('activation intent that can never settle', () {
    final unreadable = <String, void Function(File)>{
      'not json': (marker) => marker.writeAsStringSync('{"expected":'),
      'the wrong shape': (marker) => marker.writeAsStringSync('{"expected":1}'),
      'not text': (marker) => marker.writeAsBytesSync([0xC3, 0x28, 0xFF, 0xFE]),
      'empty': (marker) => marker.writeAsStringSync(''),
    };

    unreadable.forEach((name, write) {
      test('intent that is $name restores the backup', () async {
        _buildCatalog(backupPath, _lastGood);
        _buildCatalog(dbPath, '2026.03.15.000000');
        write(File('$dbPath.activation.json'));

        final db = await open();
        addTearDown(db.close);

        expect(await db.validateCatalogSnapshot(), _lastGood);
        expect(File(backupPath).existsSync(), isFalse);
        expect(File('$dbPath.activation.json').existsSync(), isFalse);
      });

      test(
        'intent that is $name with no backup opens the shipped catalog',
        () async {
          _buildCatalog(dbPath, '2026.03.15.000000');
          write(File('$dbPath.activation.json'));

          final db = await open();
          addTearDown(db.close);

          expect(await db.validateCatalogSnapshot(), _bundled);
          expect(File('$dbPath.activation.json').existsSync(), isFalse);
        },
      );
    });

    test(
      'a corrupt live catalog with no backup opens the shipped catalog',
      () async {
        File(dbPath).writeAsBytesSync([1, 2, 3, 4]);
        await recordCatalogActivation(
          dbPath: dbPath,
          expectedVersion: _update,
          previousVersion: _lastGood,
        );

        final db = await open();
        addTearDown(db.close);

        expect(await db.validateCatalogSnapshot(), _bundled);
        expect(File('$dbPath.activation.json').existsSync(), isFalse);
      },
    );

    test(
      'a missing live catalog with no backup opens the shipped catalog',
      () async {
        await recordCatalogActivation(
          dbPath: dbPath,
          expectedVersion: _update,
          previousVersion: _lastGood,
        );

        final db = await open();
        addTearDown(db.close);

        expect(await db.validateCatalogSnapshot(), _bundled);
        expect(File('$dbPath.activation.json').existsSync(), isFalse);
      },
    );

    test('recovery leaves the phone able to take the next update', () async {
      File('$dbPath.activation.json').writeAsStringSync('{"expected":');
      _buildCatalog(dbPath, '2026.03.15.000000');
      final recovered = await open();
      await recovered.close();

      _buildCatalog(stagingPath, _update);
      final result = await swapper().swap(expectedVersion: _update);

      expect(result, isA<SwapSuccess>());
      final db = (result as SwapSuccess).newDb;
      addTearDown(db.close);
      expect(await db.validateCatalogSnapshot(), _update);
    });
  });

  group('relaunch after the app died during activation', () {
    test('new catalog is good: keep it and retire the backup', () async {
      _buildCatalog(dbPath, _update);
      _buildCatalog(backupPath, _lastGood);

      final db = await open();
      addTearDown(db.close);

      expect(await db.validateCatalogSnapshot(), _update);
      expect(File(backupPath).existsSync(), isFalse);
    });

    test('new catalog is bad: restore the backup, not the bundle', () async {
      _buildCatalog(dbPath, _update, empty: true);
      _buildCatalog(backupPath, _lastGood);

      final db = await open();
      addTearDown(db.close);

      expect(await db.validateCatalogSnapshot(), _lastGood);
      expect(File(backupPath).existsSync(), isFalse);
    });

    test('new catalog is unreadable: restore the backup', () async {
      File(dbPath).writeAsStringSync('not a database');
      _buildCatalog(backupPath, _lastGood);

      final db = await open();
      addTearDown(db.close);

      expect(await db.validateCatalogSnapshot(), _lastGood);
    });

    test('died between the two renames: restore the backup', () async {
      _buildCatalog(backupPath, _lastGood);

      final db = await open();
      addTearDown(db.close);

      expect(await db.validateCatalogSnapshot(), _lastGood);
      expect(File(backupPath).existsSync(), isFalse);
    });

    test('a damaged backup never replaces a good live catalog', () async {
      _buildCatalog(dbPath, _lastGood);
      File(backupPath).writeAsStringSync('not a database');

      final db = await open();
      addTearDown(db.close);

      expect(await db.validateCatalogSnapshot(), _lastGood);
    });

    test('both bad: fall back to the bundled catalog', () async {
      File(dbPath).writeAsStringSync('not a database');
      File(backupPath).writeAsStringSync('not a database either');

      final db = await open();
      addTearDown(db.close);

      expect(await db.validateCatalogSnapshot(), _bundled);
    });
  });

  test('the app acts on every rollback that ends its handle', () {
    // main.dart's bootstrap needs Supabase, so this pins the source. Without
    // these two branches the app keeps a handle whose every read fails.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('await _adoptCatalog(restoredDb, restoredVersion)'));
    expect(
      main,
      contains(
        'else if (previousHandleInvalid) {\n          _dropDeadCatalog()',
      ),
    );
  });

  group('relaunch runs the real boot sequence at each activation step', () {
    Future<CoreDatabase> boot() async {
      await SyncService(
        appVersion: '1.0.0',
      ).activateStagedCoreDbAtPathForTest(dbPath, revalidate: true);
      return open();
    }

    Future<String> bootedVersion() async {
      final db = await boot();
      addTearDown(db.close);
      return db.validateCatalogSnapshot();
    }

    test('died before the first rename: the update installs', () async {
      _buildCatalog(dbPath, _lastGood);
      _buildCatalog(stagingPath, _update);

      expect(await bootedVersion(), _update);
      expect(File(stagingPath).existsSync(), isFalse);
      expect(File(backupPath).existsSync(), isFalse);
    });

    test('died before the first rename with a bad update: keep the '
        'current catalog', () async {
      _buildCatalog(dbPath, _lastGood);
      _buildCatalog(stagingPath, _update, empty: true);

      expect(await bootedVersion(), _lastGood);
      expect(File(stagingPath).existsSync(), isFalse);
    });

    test('died mid-download: keep the current catalog and the partial '
        'file for resume', () async {
      _buildCatalog(dbPath, _lastGood);
      File(stagingPath).writeAsStringSync('partial');
      File('$stagingPath.version').writeAsStringSync(_update);

      expect(await bootedVersion(), _lastGood);
      expect(File(stagingPath).existsSync(), isTrue);
    });

    test('died between the renames: the update installs', () async {
      _buildCatalog(backupPath, _lastGood);
      _buildCatalog(stagingPath, _update);

      expect(await bootedVersion(), _update);
      expect(File(backupPath).existsSync(), isFalse);
    });

    test('died between the renames with a bad update: restore the backup, '
        'not the bundle', () async {
      _buildCatalog(backupPath, _lastGood);
      _buildCatalog(stagingPath, _update, empty: true);

      expect(await bootedVersion(), _lastGood);
      expect(File(backupPath).existsSync(), isFalse);
    });

    test(
      'died after the renames, before confirming: keep the update',
      () async {
        _buildCatalog(dbPath, _update);
        _buildCatalog(backupPath, _lastGood);

        expect(await bootedVersion(), _update);
        expect(File(backupPath).existsSync(), isFalse);
      },
    );
  });

  group('readers holding the old handle during a swap', () {
    test('never see the new catalog, and the new handle does', () async {
      _buildCatalog(dbPath, _lastGood);
      _buildCatalog(stagingPath, _update);
      final old = await open();

      final seen = <String>{};
      var stop = false;
      Future<void> read() async {
        while (!stop) {
          try {
            seen.add(await old.validateCatalogSnapshot());
          } on Object {
            // A failed read is what the screens' error states are for.
          }
          await Future<void>.delayed(Duration.zero);
        }
      }

      final readers = [read(), read(), read()];
      final result = await swapper().swap(expectedVersion: _update);
      stop = true;
      await Future.wait(readers);

      expect(result, isA<SwapSuccess>());
      final success = result as SwapSuccess;
      addTearDown(success.newDb.close);
      expect(seen, contains(_lastGood), reason: 'the readers must have run');
      expect(seen, isNot(contains(_update)));
      expect(await success.newDb.validateCatalogSnapshot(), _update);
      await old.close();
    });

    test('a transaction open across the swap ends without the new catalog, '
        'and closing it is safe', () async {
      _buildCatalog(dbPath, _lastGood);
      _buildCatalog(stagingPath, _update);
      final old = await open();

      final inTransaction = Completer<void>();
      final finish = Completer<void>();
      final transaction = old.transaction(() async {
        final first = await old.validateCatalogSnapshot();
        inTransaction.complete();
        await finish.future;
        return (first, await old.validateCatalogSnapshot());
      });
      await inTransaction.future;

      final result = await swapper().swap(expectedVersion: _update);
      finish.complete();

      expect(result, isA<SwapSuccess>());
      addTearDown((result as SwapSuccess).newDb.close);
      try {
        final (first, second) = await transaction;
        expect(first, _lastGood);
        expect(second, _lastGood);
      } on Object catch (e) {
        expect(e, isNot(isA<TestFailure>()));
      }
      await old.close();
      expect(_versionOf(dbPath), _update);
    });

    test('a rollback leaves the new handle working while old readers fail '
        'or see the old catalog', () async {
      _buildCatalog(dbPath, _lastGood);
      _buildCatalog(stagingPath, _update, empty: true);
      final old = await open();

      final result = await swapper().swap(expectedVersion: _update);

      expect(result, isA<SwapRolledBack>());
      final rolledBack = result as SwapRolledBack;
      addTearDown(() async => rolledBack.restoredDb?.close());
      expect(await rolledBack.restoredDb!.validateCatalogSnapshot(), _lastGood);
      try {
        expect(await old.validateCatalogSnapshot(), _lastGood);
      } on Object catch (e) {
        expect(e, isNot(isA<TestFailure>()));
      }
      await old.close();
    });
  });

  test('a second update never overwrites the last confirmed catalog', () async {
    // The app died after activating an update it never confirmed, and another
    // update was staged. The backup is still the last catalog known to work.
    _buildCatalog(dbPath, _update, empty: true);
    _buildCatalog(backupPath, _lastGood);
    const next = '2026.04.01.000000';
    _buildCatalog(stagingPath, next, empty: true);

    final result = await swapper().swap(expectedVersion: next);

    expect(result, isA<SwapRolledBack>());
    addTearDown(() async => (result as SwapRolledBack).restoredDb?.close());
    expect(_versionOf(dbPath), _lastGood);
  });

  test('an older catalog republished under a newer version installs', () async {
    // The emergency rollback procedure: the updater ignores any version that
    // is not newer, so known-good content goes out under a new version number.
    _buildCatalog(dbPath, _update);
    const republished = '2026.03.02.000000';
    _buildCatalog(stagingPath, republished);

    final result = await swapper().swap(expectedVersion: republished);

    expect(result, isA<SwapSuccess>());
    addTearDown((result as SwapSuccess).newDb.close);
    expect(_versionOf(dbPath), republished);
  });
}
