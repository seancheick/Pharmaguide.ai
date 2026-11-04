import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pharmaguide/services/auth/account_database_cipher.dart';

/// Whose health data this provider tree is showing, and where it lives.
class ActiveAccount {
  const ActiveAccount({required this.scope, this.folder});

  /// A tree with no account storage behind it, as in widget tests.
  static const guest = ActiveAccount(scope: AccountStorage.guestScope);

  /// Key for per-account preferences. Never the uid itself.
  final String scope;
  final String? folder;

  String? get attachmentsPath =>
      folder == null ? null : p.join(folder!, AccountStorage.attachmentsName);

  /// Health History events keep the absolute path a file had when imported.
  /// Folders move, so only the file name in that path is still meaningful.
  File attachmentFile(String storedPath) {
    final root = attachmentsPath;
    if (root == null) return File(storedPath);
    return File(p.join(root, p.basename(storedPath)));
  }
}

/// Overridden by the bootstrap, once per account, for each provider tree.
final activeAccountProvider = Provider<ActiveAccount>(
  (ref) => ActiveAccount.guest,
);

/// The one owner of where each account's health data lives on this device
/// (ADR-013). Each account, and the guest, gets its own folder, so a read can't
/// reach another person's data by missing a filter.
class AccountStorage {
  AccountStorage({
    required this._supportDirectory,
    required this._documentsDirectory,
    this._cipher,
  });

  factory AccountStorage.production() => AccountStorage(
    supportDirectory: getApplicationSupportDirectory,
    documentsDirectory: getApplicationDocumentsDirectory,
    cipher: AccountDatabaseCipher.production,
  );

  static const guestScope = 'guest';
  static const databaseName = 'user_data.db';
  static const attachmentsName = 'attachments';
  static const _legacyAttachmentsName = 'health_history_attachments';
  static const _erasingMark = '.erasing.';

  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _documentsDirectory;
  final AccountDatabaseCipher? _cipher;

  /// Hashed so the uid stays out of file paths and preference keys.
  static String scopeFor(String? uid) => uid == null || uid.isEmpty
      ? guestScope
      : sha256.convert(utf8.encode(uid)).toString();

  Future<ActiveAccount> accountFor(String? uid) async =>
      ActiveAccount(scope: scopeFor(uid), folder: (await _folderFor(uid)).path);

  Future<Directory> _folderFor(String? uid) async {
    final support = await _supportDirectory();
    return Directory(p.join(support.path, 'users', scopeFor(uid)));
  }

  /// Creates the folder if needed and returns the database path inside it.
  Future<String> databasePathFor(String? uid) async {
    final folder = await _folderFor(uid);
    await folder.create(recursive: true);
    return p.join(folder.path, databaseName);
  }

  Future<bool> hasData(String? uid) async {
    final folder = await _folderFor(uid);
    return File(p.join(folder.path, databaseName)).exists();
  }

  /// Whether a store from before ADR-013 is still waiting to move.
  Future<bool> hasLegacyStore() async {
    final documents = await _documentsDirectory();
    final support = await _supportDirectory();
    return await File(p.join(documents.path, databaseName)).exists() ||
        await Directory(p.join(support.path, _legacyAttachmentsName)).exists();
  }

  /// First sign-in: the guest's folder becomes the account's. Only called when
  /// the account has none on this device, so health data is never merged.
  Future<void> adoptGuestFolder(String uid) async {
    final guest = await _folderFor(null);
    if (!await guest.exists()) return;
    final target = await _folderFor(uid);
    await target.parent.create(recursive: true);
    if (await target.exists()) await target.delete(recursive: true);
    await guest.rename(target.path);
  }

  /// The database goes first, so a kill partway leaves no encrypted file behind
  /// without its key, which would lock this account out if it came back.
  Future<void> delete(String? uid) async {
    final folder = await _folderFor(uid);
    if (!await folder.exists()) return;
    final database = File(p.join(folder.path, databaseName));
    if (await database.exists()) await database.delete();
    await _cipher?.forget(database.path);
    await folder.delete(recursive: true);
  }

  /// The step that decides an erase: the whole folder moves in one rename. If
  /// this throws, nothing changed. Once it returns, the data can't be opened
  /// again, and [sweepErased] removes it, even after a kill.
  Future<void> moveAsideToErase(String? uid) async {
    final folder = await _folderFor(uid);
    if (!await folder.exists()) return;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    await folder.rename('${folder.path}$_erasingMark$stamp');
  }

  /// Removes every folder [moveAsideToErase] left, and tells [removeRest] whose
  /// it was. A key that can't be forgotten is unusable with its folder gone. If
  /// anything fails this throws and the next call retries it, so [removeRest]
  /// can run twice for one folder.
  Future<void> sweepErased(
    Future<void> Function(String scope) removeRest,
  ) async {
    final users = (await _folderFor(null)).parent;
    if (!await users.exists()) return;
    await for (final entry in users.list()) {
      final name = p.basename(entry.path);
      final mark = name.indexOf(_erasingMark);
      if (entry is! Directory || mark < 0) continue;
      try {
        await _cipher?.forget(p.join(entry.path, databaseName));
      } finally {
        // The health data goes first, whatever else fails. What's left of the
        // folder is the record that the rest is still owed.
        try {
          for (final child in await entry.list().toList()) {
            await child.delete(recursive: true);
          }
        } finally {
          await removeRest(name.substring(0, mark));
        }
      }
      await entry.delete(recursive: true);
    }
  }

  /// One-way move of the single pre-ADR-013 store into [owner]'s folder.
  ///
  /// Every step is safe to repeat, so a crash finishes on the next launch, and
  /// nothing opens the database until this returns. The main file moves last.
  /// An existing target is never overwritten, so a person's data can't be
  /// replaced by another's. Colliding files are retained inside that owner's
  /// folder, so a later launch cannot assign them to the next account. A partly
  /// moved archive slot is reused, so its sidecars stay with their main file.
  Future<void> migrateLegacyStore({required String? owner}) async {
    final documents = await _documentsDirectory();
    final support = await _supportDirectory();
    final legacyDb = File(p.join(documents.path, databaseName));
    final legacyAttachments = Directory(
      p.join(support.path, _legacyAttachmentsName),
    );
    final hasDb = await legacyDb.exists();
    if (!hasDb && !await legacyAttachments.exists()) return;

    final folder = await _folderFor(owner);
    await folder.create(recursive: true);

    if (await legacyAttachments.exists()) {
      final target = Directory(p.join(folder.path, attachmentsName));
      if (!await target.exists()) {
        await legacyAttachments.rename(target.path);
      } else {
        final archive = Directory(
          await _freeArchivePath(folder, attachmentsName),
        );
        await archive.parent.create(recursive: true);
        await legacyAttachments.rename(archive.path);
      }
    }
    if (!hasDb) return;

    var target = File(p.join(folder.path, databaseName));
    if (await target.exists()) {
      target = File(await _freeArchivePath(folder, databaseName));
      await target.parent.create(recursive: true);
    }
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final sidecar = File('${legacyDb.path}$suffix');
      if (await sidecar.exists()) await sidecar.rename('${target.path}$suffix');
    }
    await legacyDb.rename(target.path);
  }

  /// The first unused spot in [folder]'s archive. An older build can recreate
  /// the shared store after any number of upgrades. Refusing would lock the
  /// person out on every launch, and replacing would lose what was kept.
  Future<String> _freeArchivePath(Directory folder, String name) async {
    for (var slot = 1; ; slot++) {
      final path = p.joinAll([
        folder.path,
        'legacy',
        if (slot > 1) '$slot',
        name,
      ]);
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.notFound) return path;
    }
  }
}
