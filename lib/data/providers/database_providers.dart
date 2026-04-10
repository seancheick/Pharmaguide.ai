import 'dart:io';

import 'package:flutter/services.dart';
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

const bundledCoreDatabaseAssetPath = 'assets/db/pharmaguide_core.db';

/// Ensures that a local core database exists before opening it.
///
/// The bundled asset must be the exact release snapshot that shipped with the
/// app. This path should never point to a partial/sample database in
/// production.
Future<void> ensureCoreDatabaseAvailable({
  required String dbPath,
  AssetBundle? bundle,
}) async {
  final dbFile = File(dbPath);
  if (await dbFile.exists()) return;

  final data = await (bundle ?? rootBundle).load(bundledCoreDatabaseAssetPath);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  await dbFile.parent.create(recursive: true);
  await dbFile.writeAsBytes(bytes, flush: true);
}

Future<CoreDatabase> openCoreDatabase({
  Directory? documentsDirectory,
  AssetBundle? bundle,
}) async {
  final dir = documentsDirectory ?? await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'pharmaguide_core.db');
  await ensureCoreDatabaseAvailable(dbPath: dbPath, bundle: bundle);
  return CoreDatabase.open(dbPath);
}

/// Open the UserDatabase at the standard application documents path.
Future<UserDatabase> openUserDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'user_data.db');
  return UserDatabase.open(dbPath);
}
