import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:sqlite3/sqlite3.dart';

/// An encrypted database whose key can't be read. The person's data is still
/// there, so the app shows a retry, never a new empty database.
class AccountKeyUnavailable implements Exception {
  const AccountKeyUnavailable();

  @override
  String toString() => 'AccountKeyUnavailable';
}

/// Where database keys are kept, by key id.
abstract interface class AccountKeyVault {
  Future<String?> read(String keyId);
  Future<void> write(String keyId, String key);
  Future<void> delete(String keyId);
}

class SecureAccountKeyVault implements AccountKeyVault {
  const SecureAccountKeyVault();

  static const _storage = FlutterSecureStorage(
    // By default Android erases the whole store on a read error, which would
    // make every encrypted database on the device unreadable for good.
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'pharmaguide_database_keys',
    ),
    // This device only, and readable while locked after the first unlock, so a
    // background wake-up doesn't find the data locked. Backups skip the database,
    // so a key that synced elsewhere would have nothing to open.
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static String _name(String keyId) => 'user_db_key_$keyId';

  @override
  Future<String?> read(String keyId) => _storage.read(key: _name(keyId));

  @override
  Future<void> write(String keyId, String key) =>
      _storage.write(key: _name(keyId), value: key);

  @override
  Future<void> delete(String keyId) => _storage.delete(key: _name(keyId));
}

final _hexKey = RegExp(r'^[0-9a-f]{64}$');
final _keyId = RegExp(r'^[0-9a-f]{32}$');

/// Unlocks [db] with [key], or throws. The error never carries the key.
void applyAccountKey(Database db, String key) {
  if (!_hexKey.hasMatch(key)) throw StateError('Malformed database key');
  try {
    db.execute('PRAGMA key = "x\'$key\'"');
  } on SqliteException catch (error) {
    throw StateError('Could not apply database key (${error.resultCode})');
  }
  // A build without encryption ignores the key and would write plaintext.
  if (db.select('PRAGMA cipher_version').isEmpty) {
    throw StateError('This build cannot encrypt');
  }
}

enum _Shape { absent, plain, encrypted }

/// What a database held before it was copied, to compare the copy against.
class _Contents {
  const _Contents(this.version, this.schema, this.rows);

  final int version;
  final List<String> schema;
  final Map<String, int> rows;
}

/// The one owner of encrypting an account's database at rest (ADR-013).
///
/// Medication data has no cloud copy, so a lost key is lost data. Two rules
/// follow, and everything here serves them:
///
/// - A database is only ever encrypted with a key an earlier launch has read
///   back. On Android a stored key reaches disk some time after the write
///   returns, and a read in the same run only sees memory. Surviving a restart
///   is the one proof that covers a kill, and a device whose store loses keys.
///   So the first session on a database stays plain, and the next one encrypts.
/// - An encrypted database with no readable key throws. Nothing here ever
///   creates a key for one, or opens a new empty database in its place.
///
/// The key id lives in the account's folder, so the guest's key travels with
/// the folder when an account adopts it, with no key store write to lose.
class AccountDatabaseCipher {
  AccountDatabaseCipher({
    required this._vault,
    this._afterStep,
    this._onFailure,
  });

  /// One instance for the app's whole run: it remembers what this run wrote.
  static final production = AccountDatabaseCipher(
    vault: const SecureAccountKeyVault(),
  );

  /// Each can be the last thing a killed migration did. Tests stop at each one.
  static const migrationSteps = [
    'old copy cleared',
    'copy written',
    'copy verified',
    'sidecars removed',
  ];

  static const _keyIdFileName = 'database_key_id';
  static const _sidecars = ['-wal', '-shm', '-journal'];
  static const _header = 'SQLite format 3\u0000';

  final AccountKeyVault _vault;
  final Future<void> Function(String step)? _afterStep;
  final void Function(Object error, StackTrace stackTrace)? _onFailure;

  final _writtenThisRun = <String>{};

  /// Returns the key to open [dbPath] with, or null to open it plain.
  ///
  /// Throws when the file is encrypted and its key can't be read. Every other
  /// failure leaves the person's plain database working, to try again next time.
  Future<String?> prepare(String dbPath) async {
    switch (await _shapeOf(dbPath)) {
      case _Shape.encrypted:
        return _keyForEncrypted(dbPath);
      case _Shape.absent:
        // Only a plain main file ever gets a copy, and it is replaced by rename.
        if (await File(_copyPath(dbPath)).exists()) {
          throw StateError('Database copy found without its database');
        }
        await _removeSidecars(dbPath);
        return _provenKey(dbPath);
      case _Shape.plain:
        final key = await _provenKey(dbPath);
        return key == null ? null : _encrypt(dbPath, key);
    }
  }

  /// Removes the key behind [dbPath], when its folder is being deleted.
  Future<void> forget(String dbPath) async {
    final id = await _readKeyId(dbPath);
    if (id == null) return;
    await _vault.delete(id);
    _writtenThisRun.remove(id);
  }

  Future<_Shape> _shapeOf(String dbPath) async {
    final file = File(dbPath);
    if (!await file.exists()) return _Shape.absent;
    final length = await file.length();
    if (length == 0) return _Shape.absent;
    if (length < _header.length) {
      throw StateError('Database file too short to identify');
    }
    final handle = await file.open();
    try {
      final start = await handle.read(_header.length);
      return latin1.decode(start) == _header ? _Shape.plain : _Shape.encrypted;
    } finally {
      await handle.close();
    }
  }

  Future<String> _keyForEncrypted(String dbPath) async {
    String? key;
    try {
      final id = await _readKeyId(dbPath);
      key = id == null ? null : await _vault.read(id);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
    }
    if (key == null || !_hexKey.hasMatch(key)) {
      throw const AccountKeyUnavailable();
    }
    return key;
  }

  /// The key an earlier launch stored and this one read back. Otherwise stores
  /// one for the next launch to prove, and returns null. Never throws, because
  /// a plain database doesn't need the store to work.
  Future<String?> _provenKey(String dbPath) async {
    try {
      final id = await _readKeyId(dbPath);
      if (id != null) {
        if (_writtenThisRun.contains(id)) return null;
        final key = await _vault.read(id);
        if (key != null && _hexKey.hasMatch(key)) return key;
      }
      await _storeNewKey(dbPath);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
    }
    return null;
  }

  Future<void> _storeNewKey(String dbPath) async {
    final id = _randomHex(16);
    await _vault.write(id, _randomHex(32));
    _writtenThisRun.add(id);
    // Renamed into place, so a kill can't leave half an id.
    final idFile = _keyIdFile(dbPath);
    final partial = File('${idFile.path}.tmp');
    await partial.writeAsString(id, flush: true);
    await partial.rename(idFile.path);
  }

  Future<String?> _readKeyId(String dbPath) async {
    final idFile = _keyIdFile(dbPath);
    if (!await idFile.exists()) return null;
    final id = (await idFile.readAsString()).trim();
    return _keyId.hasMatch(id) ? id : null;
  }

  File _keyIdFile(String dbPath) =>
      File(p.join(p.dirname(dbPath), _keyIdFileName));

  static String _copyPath(String dbPath) => '$dbPath.enc-tmp';

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return [
      for (var i = 0; i < bytes; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  /// The plain file is the person's data until the verified copy replaces it in
  /// one rename, so a kill at any point leaves one whole database to resume from.
  /// A failure keeps the plain file working and tries again next time.
  Future<String?> _encrypt(String dbPath, String key) async {
    final copy = _copyPath(dbPath);
    try {
      await _removeCopy(copy);
      await _afterStep?.call(migrationSteps[0]);
      final contents = await _inIsolate(() => _writeCopy(dbPath, copy, key));
      await _afterStep?.call(migrationSteps[1]);
      await _inIsolate(() => _verifyCopy(copy, key, contents));
      await _afterStep?.call(migrationSteps[2]);
      // Checkpointed and closed, so these hold nothing, and they would be read
      // against the encrypted file if they stayed.
      await _removeSidecars(dbPath);
      await _afterStep?.call(migrationSteps[3]);
      await File(copy).rename(dbPath);
      return key;
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace);
      try {
        await _removeCopy(copy);
      } on Object {
        // Cleared again before the next attempt.
      }
      return null;
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    final onFailure = _onFailure;
    if (onFailure != null) {
      onFailure(error, stackTrace);
    } else {
      CrashReportingService().recordError(
        error,
        stackTrace,
        hint: 'account_cipher',
      );
    }
  }

  static Future<void> _removeSidecars(String dbPath) async {
    for (final suffix in _sidecars) {
      final sidecar = File('$dbPath$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }
  }

  static Future<void> _removeCopy(String copy) async {
    for (final suffix in ['', ..._sidecars]) {
      final file = File('$copy$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  /// Copying takes as long as the database is big. Not on the UI thread.
  static Future<T> _inIsolate<T>(T Function() work) => Isolate.run(work);

  /// Runs on the isolate. Open read-write, so recovery folds in a crashed run's
  /// write-ahead log before anything is copied.
  static _Contents _writeCopy(String dbPath, String copy, String key) {
    final db = sqlite3.open(dbPath);
    try {
      if (db.select('PRAGMA cipher_version').isEmpty) {
        throw StateError('This build cannot encrypt');
      }
      final checkpoint = db.select('PRAGMA wal_checkpoint(TRUNCATE)');
      if (checkpoint.first.values.first != 0) {
        throw StateError('Database still in use');
      }
      final check = db.select('PRAGMA integrity_check');
      if (check.first.values.first != 'ok') {
        throw StateError('Database failed its integrity check');
      }
      final contents = _contentsOf(db);
      final quoted = copy.replaceAll("'", "''");
      db.execute('ATTACH DATABASE \'$quoted\' AS encrypted KEY "x\'$key\'"');
      db.select("SELECT sqlcipher_export('encrypted')");
      // The export leaves this behind, and 0 would rerun every schema migration.
      db.execute('PRAGMA encrypted.user_version = ${contents.version}');
      db.execute('DETACH DATABASE encrypted');
      return contents;
    } on SqliteException catch (error) {
      // Its text holds the statement, and so the key. It goes to crash reports.
      throw StateError('Could not write encrypted copy (${error.resultCode})');
    } finally {
      db.close();
    }
  }

  /// Runs on the isolate. Nothing replaces the person's data unless this passes.
  static void _verifyCopy(String copy, String key, _Contents expected) {
    final db = sqlite3.open(copy);
    try {
      applyAccountKey(db, key);
      if (db.select('PRAGMA cipher_integrity_check').isNotEmpty) {
        throw StateError('Encrypted copy failed its cipher check');
      }
      final check = db.select('PRAGMA integrity_check');
      if (check.first.values.first != 'ok') {
        throw StateError('Encrypted copy failed its integrity check');
      }
      final found = _contentsOf(db);
      if (found.version != expected.version) {
        throw StateError('Encrypted copy has the wrong schema version');
      }
      if (found.schema.join('\n') != expected.schema.join('\n')) {
        throw StateError('Encrypted copy has a different schema');
      }
      for (final entry in expected.rows.entries) {
        if (found.rows[entry.key] != entry.value) {
          throw StateError('Encrypted copy is missing rows');
        }
      }
    } on SqliteException catch (error) {
      throw StateError('Could not read encrypted copy (${error.resultCode})');
    } finally {
      db.close();
    }
    final start = File(copy).openSync();
    try {
      if (latin1.decode(start.readSync(_header.length)) == _header) {
        throw StateError('Copy was not encrypted');
      }
    } finally {
      start.closeSync();
    }
  }

  static _Contents _contentsOf(Database db) {
    final version = db.select('PRAGMA user_version').first.values.first as int;
    final schema = db.select(
      "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' "
      'ORDER BY type, name',
    );
    final rows = <String, int>{};
    for (final row in schema) {
      if (row['type'] != 'table') continue;
      final table = row['name'] as String;
      final quoted = table.replaceAll('"', '""');
      rows[table] =
          db.select('SELECT COUNT(*) FROM "$quoted"').first.values.first as int;
    }
    return _Contents(version, [
      for (final row in schema) '${row['type']}|${row['name']}|${row['sql']}',
    ], rows);
  }
}
