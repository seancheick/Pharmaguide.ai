import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

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
  });

  factory AccountStorage.production() => AccountStorage(
    supportDirectory: getApplicationSupportDirectory,
    documentsDirectory: getApplicationDocumentsDirectory,
  );

  static const guestScope = 'guest';
  static const databaseName = 'user_data.db';
  static const attachmentsName = 'attachments';
  static const _legacyAttachmentsName = 'health_history_attachments';

  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _documentsDirectory;

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

  Future<void> delete(String? uid) async {
    final folder = await _folderFor(uid);
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  /// One-way move of the single pre-ADR-013 store into [owner]'s folder.
  ///
  /// Every step is safe to repeat, so a crash finishes on the next launch, and
  /// nothing opens the database until this returns. The main file moves last.
  /// An existing target is never overwritten, so a person's data can't be
  /// replaced by another's; the old file stays where nothing reads it.
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
      if (!await target.exists()) await legacyAttachments.rename(target.path);
    }
    if (!hasDb) return;

    final target = File(p.join(folder.path, databaseName));
    if (await target.exists()) {
      CrashReportingService().log(
        'account_storage: account database exists, legacy store left in place',
      );
      return;
    }
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final sidecar = File('${legacyDb.path}$suffix');
      if (await sidecar.exists()) await sidecar.rename('${target.path}$suffix');
    }
    await legacyDb.rename(target.path);
  }
}
