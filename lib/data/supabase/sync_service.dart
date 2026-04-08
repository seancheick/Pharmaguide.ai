import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/supabase/supabase_client.dart';

/// Handles OTA database updates from Supabase storage.
class SyncService {
  /// Check if a new database version is available.
  /// Compares local export_manifest version against remote.
  Future<bool> isUpdateAvailable(String localVersion) async {
    try {
      // In production, fetch remote manifest from Supabase storage
      // and compare versions. For now, return false (no update).
      return false;
    } catch (_) {
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
  Future<void> downloadCoreDb() async {
    final dbPath = await getCoreDbPath();
    final stagingPath = '$dbPath.staging';

    try {
      // Look up current DB version from export_manifest.
      final manifest = await supabase
          .from('export_manifest')
          .select('db_version')
          .eq('is_current', true)
          .limit(1)
          .maybeSingle();

      final dbVersion = manifest?['db_version'] as String?;
      if (dbVersion == null) {
        throw Exception('No current export_manifest entry found');
      }

      final storagePath = 'v$dbVersion/pharmaguide_core.db';
      final bytes = await supabase.storage
          .from('pharmaguide')
          .download(storagePath);

      await File(stagingPath).writeAsBytes(bytes);

      // Atomic swap: rename staging to final
      final stagingFile = File(stagingPath);
      if (await stagingFile.exists()) {
        // Back up current DB
        final currentFile = File(dbPath);
        if (await currentFile.exists()) {
          await currentFile.rename('$dbPath.backup');
        }
        await stagingFile.rename(dbPath);
        // Clean up backup on success
        final backup = File('$dbPath.backup');
        if (await backup.exists()) {
          await backup.delete();
        }
      }
    } catch (e) {
      // Rollback: restore backup if swap failed
      final backup = File('$dbPath.backup');
      if (await backup.exists()) {
        await backup.rename(dbPath);
      }
      // Clean up staging
      final staging = File(stagingPath);
      if (await staging.exists()) {
        await staging.delete();
      }
      rethrow;
    }
  }
}
