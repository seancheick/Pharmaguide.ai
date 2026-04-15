import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/supabase_contract.dart';

/// Handles OTA database updates from Supabase storage.
class SyncService {
  /// Returns the current remote DB version published in export_manifest.
  Future<String?> fetchCurrentDbVersion() async {
    final manifest = await supabase
        .from(SupabaseContract.manifestTable)
        .select('db_version')
        .eq('is_current', true)
        .limit(1)
        .maybeSingle();

    return manifest?['db_version'] as String?;
  }

  /// Check if a new database version is available.
  /// Compares local export_manifest version against remote.
  Future<bool> isUpdateAvailable(String localVersion) async {
    try {
      final remoteVersion = await fetchCurrentDbVersion();
      return remoteVersion != null && remoteVersion != localVersion;
    } on Object {
      return false;
    }
  }

  /// Get the path where the core database should live.
  Future<String> getCoreDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'pharmaguide_core.db');
  }

  /// Get the path where the user database should live.
  Future<String> getUserDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'user_data.db');
  }

  /// Download the core database from Supabase storage.
  /// Fetches the current version from export_manifest, then downloads
  /// from the `pharmaguide` bucket at `v{db_version}/pharmaguide_core.db`.
  Future<String> downloadCoreDb({String? expectedVersion}) async {
    final validatedVersion = await stageCoreDbDownload(
      expectedVersion: expectedVersion,
    );
    await activateStagedCoreDbIfPresent();
    return validatedVersion;
  }

  /// Downloads the latest database into staging and validates it.
  Future<String> stageCoreDbDownload({String? expectedVersion}) async {
    final dbPath = await getCoreDbPath();
    final stagingPath = '$dbPath.staging';

    try {
      final dbVersion = expectedVersion ?? await fetchCurrentDbVersion();
      if (dbVersion == null) {
        throw Exception('No current export_manifest entry found');
      }

      final storagePath = SupabaseContract.coreDbPath(dbVersion);
      final bytes = await supabase.storage
          .from(SupabaseContract.storageBucket)
          .download(storagePath);

      await File(stagingPath).writeAsBytes(bytes, flush: true);

      final validatedVersion = await _validateStagedDatabase(
        stagingPath,
        expectedVersion: dbVersion,
      );
      return validatedVersion;
    } catch (e) {
      // Clean up staging
      final staging = File(stagingPath);
      if (await staging.exists()) {
        await staging.delete();
      }
      rethrow;
    }
  }

  /// Promotes a validated staging database into the live path.
  /// Safe to call repeatedly; it no-ops if no staged file exists.
  Future<void> activateStagedCoreDbIfPresent() async {
    final dbPath = await getCoreDbPath();
    final stagingPath = '$dbPath.staging';
    final backupPath = '$dbPath.backup';
    final stagingFile = File(stagingPath);
    if (!await stagingFile.exists()) {
      return;
    }

    final currentFile = File(dbPath);
    final backupFile = File(backupPath);
    var backedUpCurrent = false;

    try {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      if (await currentFile.exists()) {
        await currentFile.rename(backupPath);
        backedUpCurrent = true;
      }

      await stagingFile.rename(dbPath);

      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (_) {
      if (backedUpCurrent && await backupFile.exists()) {
        if (await currentFile.exists()) {
          await currentFile.delete();
        }
        await backupFile.rename(dbPath);
      }
      rethrow;
    } finally {
      if (await stagingFile.exists()) {
        await stagingFile.delete();
      }
    }
  }

  /// Validates that a freshly-downloaded staging DB matches the version we
  /// thought we were downloading.
  ///
  /// [expectedVersion] is the `db_version` build timestamp (e.g.
  /// `"2026.04.10.222555"`) pulled from the remote `export_manifest` table.
  /// [CoreDatabase.validateCatalogSnapshot] reads the same `db_version`
  /// field from the DB's embedded `export_manifest` key-value table, so the
  /// two values must match byte-for-byte. A mismatch means Supabase Storage
  /// served us a file that disagrees with its own manifest row — we refuse
  /// to activate it.
  Future<String> _validateStagedDatabase(
    String dbPath, {
    required String expectedVersion,
  }) async {
    final db = CoreDatabase.open(dbPath);
    try {
      final validatedVersion = await db.validateCatalogSnapshot();
      if (validatedVersion != expectedVersion) {
        throw StateError(
          'Downloaded catalog version mismatch: '
          'expected db_version $expectedVersion, got $validatedVersion. '
          'The remote Storage file disagrees with the remote manifest row.',
        );
      }
      return validatedVersion;
    } finally {
      await db.close();
    }
  }
}
