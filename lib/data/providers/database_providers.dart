import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';

/// Provides the singleton CoreDatabase instance (read-only product data).
/// Must be overridden at app startup with a real instance.
final coreDatabaseProvider = Provider<CoreDatabase>((ref) {
  throw UnimplementedError(
    'coreDatabaseProvider must be overridden at app startup',
  );
});

/// Provides the singleton UserDatabase instance.
/// Lazily opens the database on first access.
final userDatabaseProvider = Provider<UserDatabase>((ref) {
  throw UnimplementedError(
    'userDatabaseProvider must be overridden at app startup',
  );
});

/// Open the CoreDatabase from the assets/db directory.
Future<CoreDatabase> openCoreDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'pharmaguide_core.db');
  return CoreDatabase.open(dbPath);
}

/// Open the UserDatabase at the standard application documents path.
Future<UserDatabase> openUserDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'user_data.db');
  return UserDatabase.open(dbPath);
}
