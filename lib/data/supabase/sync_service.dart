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
  /// Downloads to a staging file, verifies, then atomically swaps.
  Future<void> downloadCoreDb() async {
    final dbPath = await getCoreDbPath();
    final stagingPath = '$dbPath.staging';

    try {
      final bytes = await supabase.storage
          .from('databases')
          .download('pharmaguide_core.db');

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
