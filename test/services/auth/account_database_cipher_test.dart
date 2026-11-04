// Encrypting each account's database (ADR-013) against the real SQLCipher
// library and real files. Medication data has no cloud copy, so the point of
// most of these is what happens when the step in between doesn't finish.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/services/auth/account_database_cipher.dart';
import 'package:pharmaguide/services/auth/account_storage.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

const _canary = 'WarfarinCanary';

class _Vault implements AccountKeyVault {
  final keys = <String, String>{};
  Object? readError;
  Object? writeError;
  bool loseWrites = false;
  int writes = 0;

  @override
  Future<String?> read(String keyId) async {
    if (readError != null) throw readError!;
    return keys[keyId];
  }

  @override
  Future<void> write(String keyId, String key) async {
    if (writeError != null) throw writeError!;
    writes++;
    if (!loseWrites) keys[keyId] = key;
  }

  @override
  Future<void> delete(String keyId) async {
    keys.remove(keyId);
  }
}

class _Killed implements Exception {}

Future<void> _addTo(UserDatabase db, String name) => db.addToStack(
  UserStacksLocalCompanion.insert(
    id: 'id-$name',
    name: name,
    type: const Value('medication'),
  ),
);

Future<List<String>> _names(UserDatabase db) async => [
  for (final row in await db.getActiveStack()) row.name,
];

bool _isPlain(String path) =>
    latin1.decode(File(path).readAsBytesSync().take(15).toList()) ==
    'SQLite format 3';

bool _contains(String path, String needle) =>
    latin1.decode(File(path).readAsBytesSync()).contains(needle);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String path;
  late _Vault vault;

  /// A new run of the app: remembers nothing, finds what's on disk.
  AccountDatabaseCipher launch({
    Future<void> Function(String step)? afterStep,
    void Function(Object error, StackTrace stackTrace)? onFailure,
  }) => AccountDatabaseCipher(
    vault: vault,
    afterStep: afterStep,
    onFailure: onFailure ?? (_, _) {},
  );

  /// A first session: the database is created plain and a key is stored.
  Future<void> firstSession(String dbPath, {String name = _canary}) async {
    expect(await launch().prepare(dbPath), isNull);
    final db = UserDatabase.open(dbPath);
    await _addTo(db, name);
    await db.close();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('account cipher');
    final folder = Directory(p.join(root.path, 'users', 'owner-a'))
      ..createSync(recursive: true);
    path = p.join(folder.path, AccountStorage.databaseName);
    vault = _Vault();
  });

  tearDown(() => root.delete(recursive: true));

  test('this build can encrypt: a plain SQLite would ignore the key', () {
    final db = raw.sqlite3.openInMemory();
    addTearDown(db.close);
    expect(db.select('PRAGMA cipher_version'), isNotEmpty);
  });

  group('a key is only trusted once it survives a restart', () {
    test('the first session stays plain and stores a key', () async {
      await firstSession(path);
      expect(_isPlain(path), isTrue);
      expect(vault.keys, hasLength(1));
    });

    test('the same run never encrypts with the key it just stored', () async {
      final cipher = launch();
      expect(await cipher.prepare(path), isNull);
      final db = UserDatabase.open(path);
      await _addTo(db, _canary);
      await db.close();
      expect(await cipher.prepare(path), isNull, reason: 'a switch and back');
      expect(_isPlain(path), isTrue);
      expect(vault.writes, 1);
    });

    test(
      'the next launch encrypts, and nothing is left in plaintext',
      () async {
        await firstSession(path);
        final key = await launch().prepare(path);

        expect(key, isNotNull);
        expect(_isPlain(path), isFalse);
        expect(_contains(path, _canary), isFalse);
        final db = UserDatabase.open(path, key: key);
        addTearDown(db.close);
        expect(await _names(db), [_canary]);
      },
    );

    test(
      'a store that lost the key means no encryption, and no loss',
      () async {
        vault.loseWrites = true;
        await firstSession(path);

        expect(await launch().prepare(path), isNull);
        expect(_isPlain(path), isTrue);
        final db = UserDatabase.open(path);
        addTearDown(db.close);
        expect(await _names(db), [_canary]);
      },
    );

    test('a broken store leaves a new database working', () async {
      vault.writeError = StateError('keystore down');
      await firstSession(path);
      expect(_isPlain(path), isTrue);

      vault.writeError = null;
      expect(await launch().prepare(path), isNull, reason: 'stores one now');
      expect(await launch().prepare(path), isNotNull, reason: 'and proves it');
    });

    test(
      'a proven key with no file yet starts the database encrypted',
      () async {
        expect(await launch().prepare(path), isNull);
        final key = await launch().prepare(path);
        expect(key, isNotNull);
        final db = UserDatabase.open(path, key: key);
        await _addTo(db, _canary);
        await db.close();
        expect(_isPlain(path), isFalse);
        expect(_contains(path, _canary), isFalse);
      },
    );
  });

  group('an encrypted database', () {
    late String key;

    setUp(() async {
      await firstSession(path);
      key = (await launch().prepare(path))!;
    });

    test('opens with its key and keeps its data', () async {
      expect(await launch().prepare(path), key);
      final db = UserDatabase.open(path, key: key);
      addTearDown(db.close);
      expect(await _names(db), [_canary]);
    });

    test('a missing key fails closed: no new key, no new database', () async {
      vault.keys.clear();
      final writes = vault.writes;
      final before = File(path).readAsBytesSync();
      await expectLater(
        launch().prepare(path),
        throwsA(isA<AccountKeyUnavailable>()),
      );
      expect(vault.writes, writes);
      expect(vault.keys, isEmpty);
      expect(File(path).readAsBytesSync(), before);
    });

    test('an unreadable key fails closed the same way', () async {
      vault.readError = StateError('keystore locked');
      await expectLater(
        launch().prepare(path),
        throwsA(isA<AccountKeyUnavailable>()),
      );
      vault.readError = null;
      expect(await launch().prepare(path), key, reason: 'it comes back');
    });

    group('only a key the store reports gone is lost for good', () {
      File idFile() => File(p.join(p.dirname(path), 'database_key_id'));

      test('absent from the store', () async {
        vault.keys.clear();
        await expectLater(
          launch().prepare(path),
          throwsA(isA<AccountKeyLost>()),
        );
      });

      test('in the store, but not a usable key', () async {
        vault.keys[idFile().readAsStringSync().trim()] = 'not a key';
        await expectLater(
          launch().prepare(path),
          throwsA(isA<AccountKeyLost>()),
        );
      });

      test('a store read that errors can be temporary', () async {
        vault.readError = StateError('keystore locked');
        await expectLater(
          launch().prepare(path),
          throwsA(
            allOf(isA<AccountKeyUnavailable>(), isNot(isA<AccountKeyLost>())),
          ),
        );
      });

      test('a missing key id means the store was never asked', () async {
        idFile().deleteSync();
        await expectLater(
          launch().prepare(path),
          throwsA(
            allOf(isA<AccountKeyUnavailable>(), isNot(isA<AccountKeyLost>())),
          ),
        );
      });

      test('a damaged key id means the store was never asked', () async {
        idFile().writeAsStringSync('damaged');
        await expectLater(
          launch().prepare(path),
          throwsA(
            allOf(isA<AccountKeyUnavailable>(), isNot(isA<AccountKeyLost>())),
          ),
        );
      });

      test('a damaged plain file with no key id is not a lost key', () async {
        idFile().deleteSync();
        File(path).writeAsBytesSync(List.filled(4096, 7));
        await expectLater(
          launch().prepare(path),
          throwsA(
            allOf(isA<AccountKeyUnavailable>(), isNot(isA<AccountKeyLost>())),
          ),
        );
      });
    });

    test('a missing key id fails closed too', () async {
      File(p.join(p.dirname(path), 'database_key_id')).deleteSync();
      final writes = vault.writes;
      await expectLater(
        launch().prepare(path),
        throwsA(isA<AccountKeyUnavailable>()),
      );
      expect(vault.writes, writes);
    });

    test('the wrong key fails on open and changes nothing', () async {
      final before = File(path).readAsBytesSync();
      final db = UserDatabase.open(path, key: 'b' * 64);
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
      await db.close();
      expect(File(path).readAsBytesSync(), before);
    });

    test('no key at all fails on open: never read as a new database', () async {
      final db = UserDatabase.open(path);
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
      await db.close();
      expect(_isPlain(path), isFalse);
    });
  });

  group('migrating an existing plain database', () {
    test(
      'keeps every row and the schema version, with no plaintext left',
      () async {
        await firstSession(path);
        expect(_contains(path, _canary), isTrue, reason: 'seed is plaintext');

        final key = await launch().prepare(path);

        expect(_isPlain(path), isFalse);
        expect(_contains(path, _canary), isFalse);
        for (final suffix in const ['-wal', '-shm', '-journal']) {
          expect(File('$path$suffix').existsSync(), isFalse, reason: suffix);
        }
        expect(File('$path.enc-tmp').existsSync(), isFalse);

        final db = UserDatabase.open(path, key: key);
        addTearDown(db.close);
        expect(await _names(db), [_canary]);
        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.data.values.first, db.schemaVersion);
      },
    );

    test('takes in rows still sitting in the write-ahead log', () async {
      await firstSession(path);
      // Copies the files of a live connection, as a crash would leave them.
      final live = raw.sqlite3.open(path)
        ..execute('PRAGMA wal_autocheckpoint=0')
        ..execute(
          'INSERT INTO user_stacks_local (id, name, type) '
          "VALUES ('wal', 'OnlyInWal', 'medication')",
        );
      final crashed = p.join(root.path, 'users', 'owner-b');
      Directory(crashed).createSync();
      final target = p.join(crashed, AccountStorage.databaseName);
      for (final suffix in const ['', '-wal']) {
        File('$path$suffix').copySync('$target$suffix');
      }
      File(
        p.join(p.dirname(path), 'database_key_id'),
      ).copySync(p.join(crashed, 'database_key_id'));
      expect(File('$target-wal').lengthSync(), greaterThan(0));
      live.close();

      final key = await launch().prepare(target);
      final db = UserDatabase.open(target, key: key);
      addTearDown(db.close);
      expect(await _names(db), containsAll([_canary, 'OnlyInWal']));
      expect(_contains(target, 'OnlyInWal'), isFalse);
    });

    for (final step in AccountDatabaseCipher.migrationSteps) {
      test('killed after "$step" resumes and loses nothing', () async {
        await firstSession(path);

        final killed = launch(
          afterStep: (done) async {
            if (done == step) throw _Killed();
          },
        );
        expect(await killed.prepare(path), isNull);
        final plain = UserDatabase.open(path);
        expect(await _names(plain), [
          _canary,
        ], reason: 'plain file still whole');
        await plain.close();

        final key = await launch().prepare(path);
        final db = UserDatabase.open(path, key: key);
        addTearDown(db.close);
        expect(await _names(db), [_canary]);
        expect(_isPlain(path), isFalse);
        expect(File('$path.enc-tmp').existsSync(), isFalse);
      });
    }

    test(
      'a leftover write-ahead log is not read against the new file',
      () async {
        await firstSession(path);
        final otherPath = p.join(root.path, 'other.db');
        final other = raw.sqlite3.open(otherPath)
          ..execute('PRAGMA journal_mode=WAL')
          ..execute('PRAGMA wal_autocheckpoint=0')
          ..execute('CREATE TABLE t (x)')
          ..execute('INSERT INTO t VALUES (1)');
        addTearDown(other.close);

        final key = await launch(
          afterStep: (step) async {
            if (step == AccountDatabaseCipher.migrationSteps[2]) {
              File('$otherPath-wal').copySync('$path-wal');
            }
          },
        ).prepare(path);

        final db = UserDatabase.open(path, key: key);
        addTearDown(db.close);
        expect(await _names(db), [_canary]);
      },
    );

    test('a torn copy from a hard kill is replaced', () async {
      await firstSession(path);
      File('$path.enc-tmp').writeAsBytesSync(List.filled(4096, 7));
      File('$path.enc-tmp-journal').writeAsBytesSync(List.filled(512, 7));

      final key = await launch().prepare(path);

      expect(File('$path.enc-tmp').existsSync(), isFalse);
      expect(File('$path.enc-tmp-journal').existsSync(), isFalse);
      final db = UserDatabase.open(path, key: key);
      addTearDown(db.close);
      expect(await _names(db), [_canary]);
    });

    test('a damaged plain file is never replaced by its copy', () async {
      await firstSession(path);
      final bytes = BytesBuilder()
        ..add(utf8.encode('SQLite format 3\u0000'))
        ..add(List.filled(8192, 0));
      File(path).writeAsBytesSync(bytes.toBytes());
      for (final suffix in const ['-wal', '-shm']) {
        final sidecar = File('$path$suffix');
        if (sidecar.existsSync()) sidecar.deleteSync();
      }
      final before = File(path).readAsBytesSync();

      expect(await launch().prepare(path), isNull);
      expect(File(path).readAsBytesSync(), before);
      expect(File('$path.enc-tmp').existsSync(), isFalse);
    });

    test('a file too short to identify fails closed', () async {
      File(path).writeAsBytesSync([1, 2, 3]);
      await expectLater(launch().prepare(path), throwsStateError);
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });

    test('a copy with no database behind it fails closed', () async {
      File('$path.enc-tmp').writeAsBytesSync(List.filled(4096, 7));
      await expectLater(launch().prepare(path), throwsStateError);
      expect(File('$path.enc-tmp').existsSync(), isTrue);
    });

    test('crash reports never carry the key', () async {
      await firstSession(path);
      final reports = <String>[];
      final failing = launch(
        // SQLite can't attach a folder, so the statement holding the key fails.
        afterStep: (step) async {
          if (step == AccountDatabaseCipher.migrationSteps[0]) {
            Directory('$path.enc-tmp').createSync();
          }
        },
        onFailure: (error, _) => reports.add('$error'),
      );

      expect(await failing.prepare(path), isNull);

      expect(reports, isNotEmpty);
      for (final report in reports) {
        for (final key in vault.keys.values) {
          expect(report, isNot(contains(key)));
        }
      }
    });
  });

  group('through the switch guard', () {
    const a = 'account-a';
    const b = 'account-b';
    late AccountStorage storage;
    late AccountSwitchGuard guard;
    late AccountDatabaseCipher cipher;

    /// A new run of the app, with the key store and files it left behind.
    AccountSwitchGuard restart() {
      cipher = launch();
      storage = AccountStorage(
        supportDirectory: () async => root,
        documentsDirectory: () async => root,
        cipher: cipher,
      );
      return AccountSwitchGuard(
        ownerStore: AccountOwnerStore(),
        storage: storage,
        openDatabase: (dbPath) async {
          final key = await cipher.prepare(dbPath);
          return UserDatabase.open(dbPath, key: key);
        },
      );
    }

    String dbFor(String? uid) => p.join(
      root.path,
      'users',
      AccountStorage.scopeFor(uid),
      AccountStorage.databaseName,
    );

    setUp(() => guard = restart());
    tearDown(() => guard.close());

    /// Ends the run in progress and boots the next one as [uid].
    Future<void> nextLaunch(String? uid) async {
      await guard.close();
      guard = restart();
      await guard.boot(sessionUid: uid);
    }

    group('starting over after a lost key, against real files', () {
      /// Encrypts [uid]'s database with [name] in it, then forgets its key.
      Future<void> lockedAccount(String uid, {String name = 'A med'}) async {
        await nextLaunch(uid);
        await _addTo(guard.database!, name);
        await nextLaunch(uid);
        expect(_isPlain(dbFor(uid)), isFalse);
        final idFile = File(p.join(p.dirname(dbFor(uid)), 'database_key_id'));
        vault.keys.remove(idFile.readAsStringSync().trim());
      }

      test(
        'erases that account only, and gives it a new empty start',
        () async {
          await lockedAccount(a);
          final lockedKeys = vault.keys.length;
          await nextLaunch(b);
          await _addTo(guard.database!, 'B med');
          await nextLaunch(b);
          await guard.onAuthEvent(event: AuthChangeEvent.signedOut, uid: null);
          await _addTo(guard.database!, 'Guest med');
          final bBytes = File(dbFor(b)).readAsBytesSync();
          expect(vault.keys.length, greaterThan(lockedKeys));
          final bKeys = Map.of(vault.keys);
          final attachment = File(
            p.join(p.dirname(dbFor(a)), 'attachments', 'scan.jpg'),
          )..createSync(recursive: true);

          await nextLaunch(a);
          expect(guard.database, isNull);
          expect(guard.canStartOver, isTrue);
          await guard.startOver();

          expect(guard.ownerUid, a);
          expect(await _names(guard.database!), isEmpty);
          expect(attachment.existsSync(), isFalse);
          expect(guard.canStartOver, isFalse);
          expect(File(dbFor(b)).readAsBytesSync(), bBytes);
          bKeys.forEach((id, key) => expect(vault.keys[id], key));

          await guard.onAuthEvent(event: AuthChangeEvent.signedOut, uid: null);
          expect(await _names(guard.database!), ['Guest med']);
          await guard.onAuthEvent(event: AuthChangeEvent.signedIn, uid: b);
          expect(await _names(guard.database!), ['B med']);
        },
      );

      test(
        'a stored key that is not usable is removed with the data',
        () async {
          await nextLaunch(a);
          await _addTo(guard.database!, 'A med');
          await nextLaunch(a);
          final id = File(
            p.join(p.dirname(dbFor(a)), 'database_key_id'),
          ).readAsStringSync().trim();
          vault.keys[id] = 'not a key';

          await nextLaunch(a);
          expect(guard.canStartOver, isTrue);
          await guard.startOver();

          expect(vault.keys.containsKey(id), isFalse);
          expect(await _names(guard.database!), isEmpty);
        },
      );

      test('a store read that errors never reaches the erase', () async {
        await nextLaunch(a);
        await _addTo(guard.database!, 'A med');
        await nextLaunch(a);
        vault.readError = StateError('keystore locked');
        final before = File(dbFor(a)).readAsBytesSync();

        await nextLaunch(a);

        expect(guard.database, isNull);
        expect(guard.canStartOver, isFalse);
        await expectLater(guard.startOver(), throwsStateError);
        expect(File(dbFor(a)).readAsBytesSync(), before);
        vault.readError = null;
        await guard.retry();
        expect(await _names(guard.database!), ['A med']);
      });

      test('a damaged database with its key never reaches the erase', () async {
        await nextLaunch(a);
        await _addTo(guard.database!, 'A med');
        await nextLaunch(a);
        await guard.close();
        File(dbFor(a)).writeAsBytesSync(List.filled(8192, 7));
        final before = File(dbFor(a)).readAsBytesSync();
        guard = restart();

        await guard.boot(sessionUid: a);

        expect(guard.database, isNull);
        expect(guard.canStartOver, isFalse);
        await expectLater(guard.startOver(), throwsStateError);
        expect(File(dbFor(a)).readAsBytesSync(), before);
      });
    });

    test(
      'each account gets its own key, and neither opens the other',
      () async {
        await guard.boot(sessionUid: a);
        await _addTo(guard.database!, 'A med');
        await nextLaunch(a);
        expect(_isPlain(dbFor(a)), isFalse);

        await guard.onAuthEvent(event: AuthChangeEvent.signedOut, uid: null);
        await guard.onAuthEvent(event: AuthChangeEvent.signedIn, uid: b);
        await _addTo(guard.database!, 'B med');
        await nextLaunch(b);
        expect(_isPlain(dbFor(b)), isFalse);
        await guard.close();

        final keyB = await launch().prepare(dbFor(b));
        expect(await launch().prepare(dbFor(a)), isNot(keyB));
        final crossed = UserDatabase.open(dbFor(a), key: keyB);
        await expectLater(
          crossed.customSelect('SELECT 1').get(),
          throwsA(anything),
        );
        await crossed.close();
        expect(_contains(dbFor(a), 'A med'), isFalse);
      },
    );

    test(
      'a lost key shows the retry state, and the data returns with it',
      () async {
        await guard.boot(sessionUid: a);
        await _addTo(guard.database!, 'A med');
        await nextLaunch(a);
        await guard.close();
        final saved = Map<String, String>.of(vault.keys);
        vault.keys.clear();
        final before = File(dbFor(a)).readAsBytesSync();

        guard = restart();
        await guard.boot(sessionUid: a);

        expect(guard.database, isNull, reason: 'never an empty database');
        expect(File(dbFor(a)).readAsBytesSync(), before);
        expect(vault.keys, isEmpty);
        expect(File(dbFor(null)).existsSync(), isFalse);

        vault.keys.addAll(saved);
        await guard.retry();
        expect(await _names(guard.database!), ['A med']);
      },
    );

    test(
      'first sign-in carries the guest key with no key store write',
      () async {
        await guard.boot(sessionUid: null);
        await _addTo(guard.database!, 'Guest med');
        await nextLaunch(null);
        expect(_isPlain(dbFor(null)), isFalse);
        final writes = vault.writes;

        await guard.onAuthEvent(event: AuthChangeEvent.signedIn, uid: a);

        expect(await _names(guard.database!), ['Guest med']);
        expect(_isPlain(dbFor(a)), isFalse);
        expect(vault.writes, writes, reason: 'nothing a kill could lose');
        await nextLaunch(a);
        expect(await _names(guard.database!), ['Guest med']);
      },
    );

    test('a new guest after adoption gets a new key', () async {
      await guard.boot(sessionUid: null);
      await _addTo(guard.database!, 'Guest med');
      await nextLaunch(null);
      await guard.onAuthEvent(event: AuthChangeEvent.signedIn, uid: a);
      await guard.onAuthEvent(event: AuthChangeEvent.signedOut, uid: null);

      expect(await _names(guard.database!), isEmpty);
      expect(vault.keys, hasLength(2));
      expect(vault.keys.values.toSet(), hasLength(2));
    });

    test('remove deletes the folder and the key', () async {
      await guard.boot(sessionUid: a);
      await _addTo(guard.database!, 'A med');
      await nextLaunch(a);
      final idFile = File(p.join(p.dirname(dbFor(a)), 'database_key_id'));
      final id = idFile.readAsStringSync();
      expect(vault.keys, contains(id));

      await guard.removeAccountData(a);

      expect(File(dbFor(a)).existsSync(), isFalse);
      expect(Directory(p.dirname(dbFor(a))).existsSync(), isFalse);
      expect(vault.keys, isNot(contains(id)));
      expect(guard.database, isNotNull, reason: 'now the guest');
    });

    test('an account signing back in after remove starts clean', () async {
      await guard.boot(sessionUid: a);
      await _addTo(guard.database!, 'A med');
      await nextLaunch(a);
      await guard.removeAccountData(a);

      await guard.onAuthEvent(event: AuthChangeEvent.signedIn, uid: a);

      expect(guard.database, isNotNull);
      expect(await _names(guard.database!), isEmpty);
    });
  });
}
