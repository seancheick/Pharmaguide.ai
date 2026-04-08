import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/services/analytics_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize crash reporting (stub — safe to call, never throws)
  await CrashReportingService().initialize();

  // Initialize analytics (stub — safe to call, never throws)
  await AnalyticsService().initialize();

  // Initialize Supabase (will use placeholders if no env vars set)
  bool supabaseReady = false;
  try {
    await initSupabase();
    supabaseReady = true;
  } on Exception catch (e) {
    debugPrint('Supabase init skipped: $e');
  }

  // Download core DB on first launch if it doesn't exist
  final dir = await getApplicationDocumentsDirectory();
  final coreDbPath = p.join(dir.path, 'pharmaguide_core.db');
  if (!File(coreDbPath).existsSync() && supabaseReady) {
    try {
      debugPrint('First launch — downloading core database...');
      await SyncService().downloadCoreDb();
      debugPrint('Core database downloaded successfully.');
    } on Exception catch (e) {
      debugPrint('Core DB download failed: $e');
    }
  }

  // Open databases
  final userDb = await openUserDatabase();
  final coreDb = await openCoreDatabase();

  runApp(
    ProviderScope(
      overrides: [
        userDatabaseProvider.overrideWithValue(userDb),
        coreDatabaseProvider.overrideWithValue(coreDb),
      ],
      child: const PharmaGuideApp(),
    ),
  );
}
