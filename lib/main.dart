import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';
import 'package:pharmaguide/services/analytics_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';

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

  final userDb = await openUserDatabase();
  final hasSeenOnboarding = await OnboardingPrefs.hasSeen();

  runApp(PharmaGuideBootstrap(
    userDb: userDb,
    supabaseReady: supabaseReady,
    hasSeenOnboarding: hasSeenOnboarding,
  ));
}

class PharmaGuideBootstrap extends StatefulWidget {
  final UserDatabase userDb;
  final bool supabaseReady;
  final bool hasSeenOnboarding;

  const PharmaGuideBootstrap({
    super.key,
    required this.userDb,
    required this.supabaseReady,
    required this.hasSeenOnboarding,
  });

  @override
  State<PharmaGuideBootstrap> createState() => _PharmaGuideBootstrapState();
}

class _PharmaGuideBootstrapState extends State<PharmaGuideBootstrap> {
  final SyncService _syncService = SyncService();

  CoreDatabase? _coreDb;
  String? _activeCatalogVersion;
  String? _catalogUnavailableReason;
  bool _catalogAvailable = false;
  bool _bootstrapped = false;
  bool _syncInFlight = false;
  int _scopeVersion = 0;
  Timer? _catalogRefreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrapCatalog());
  }

  @override
  void dispose() {
    _catalogRefreshTimer?.cancel();
    unawaited(_coreDb?.close());
    unawaited(widget.userDb.close());
    super.dispose();
  }

  Future<void> _bootstrapCatalog() async {
    CoreDatabase? initialDb;
    String? initialReason;

    if (widget.supabaseReady) {
      try {
        await _syncService.activateStagedCoreDbIfPresent();
      } on Object catch (e) {
        debugPrint('Catalog staged activation failed: $e');
      }
    }

    try {
      initialDb = await _openValidatedCatalog();
    } on Object catch (e) {
      debugPrint('Local/bundled catalog unavailable: $e');
    }

    if (initialDb == null && widget.supabaseReady) {
      try {
        debugPrint('No verified local catalog. Attempting network download...');
        await _syncService.downloadCoreDb();
        initialDb = await _openValidatedCatalog();
      } on Object catch (e) {
        initialReason = _unavailableReason(includeRetryHint: true);
        debugPrint('Initial catalog download failed: $e');
      }
    }

    if (initialDb == null && initialReason == null) {
      initialReason = _unavailableReason(includeRetryHint: widget.supabaseReady);
    }

    if (!mounted) {
      await initialDb?.close();
      return;
    }

    setState(() {
      _coreDb = initialDb;
      _catalogAvailable = initialDb != null;
      _catalogUnavailableReason = initialDb == null ? initialReason : null;
      _bootstrapped = true;
      _scopeVersion++;
    });

    _scheduleCatalogRefresh(initialDelay: const Duration(seconds: 10));
  }

  Future<CoreDatabase> _openValidatedCatalog() async {
    final db = await openCoreDatabase();
    try {
      _activeCatalogVersion = await db.validateCatalogSnapshot();
      return db;
    } on Object {
      await db.close();
      rethrow;
    }
  }

  Future<void> _retryCatalogLoad() async {
    await _refreshCatalogIfNeeded(forceDownload: true);
  }

  void _scheduleCatalogRefresh({Duration? initialDelay}) {
    _catalogRefreshTimer?.cancel();
    if (!widget.supabaseReady) return;

    final delay =
        initialDelay ?? (_catalogAvailable ? const Duration(hours: 1) : const Duration(minutes: 5));

    _catalogRefreshTimer = Timer(delay, () {
      unawaited(_refreshCatalogIfNeeded());
    });
  }

  Future<void> _refreshCatalogIfNeeded({bool forceDownload = false}) async {
    if (!widget.supabaseReady || _syncInFlight) {
      return;
    }

    _syncInFlight = true;
    try {
      final remoteVersion = await _syncService.fetchCurrentDbVersion();
      if (remoteVersion == null) {
        return;
      }

      final shouldDownload =
          forceDownload || remoteVersion != _activeCatalogVersion || _coreDb == null;
      if (!shouldDownload) {
        return;
      }

      final downloadedVersion = await _syncService.stageCoreDbDownload(
        expectedVersion: remoteVersion,
      );

      if (_coreDb != null) {
        debugPrint(
          'Catalog update $downloadedVersion staged for next app start. '
          'Current session remains on $_activeCatalogVersion.',
        );
        return;
      }

      await _syncService.activateStagedCoreDbIfPresent();
      final nextDb = await _openValidatedCatalog();

      if (!mounted) {
        await nextDb.close();
        return;
      }

      setState(() {
        _coreDb = nextDb;
        _activeCatalogVersion = downloadedVersion;
        _catalogAvailable = true;
        _catalogUnavailableReason = null;
        _scopeVersion++;
      });
    } on Object catch (e) {
      debugPrint('Catalog refresh failed: $e');
      if (mounted && _coreDb == null) {
        setState(() {
          _catalogAvailable = false;
          _catalogUnavailableReason =
              _unavailableReason(includeRetryHint: true);
        });
      }
    } finally {
      _syncInFlight = false;
      _scheduleCatalogRefresh();
    }
  }

  String _unavailableReason({required bool includeRetryHint}) {
    const baseMessage =
        'Verified product catalog unavailable. PharmaGuide will not show product results until a validated catalog snapshot is installed.';
    if (!includeRetryHint) {
      return baseMessage;
    }
    return '$baseMessage Connect to the internet and retry to download the latest catalog.';
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootstrapped) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return ProviderScope(
      key: ValueKey(_scopeVersion),
      overrides: [
        userDatabaseProvider.overrideWithValue(widget.userDb),
        if (_coreDb != null) coreDatabaseProvider.overrideWithValue(_coreDb!),
      ],
      // Register the stack sync auto-listener as soon as the ProviderScope
      // mounts. The Consumer reads [stackSyncListenerProvider] once; the
      // provider itself calls `ref.keepAlive()` so its auth + connectivity
      // subscriptions survive disposal of this Consumer.
      child: Consumer(
        builder: (context, ref, child) {
          ref.watch(stackSyncListenerProvider);
          return child!;
        },
        child: PharmaGuideApp(
          catalogAvailable: _catalogAvailable,
          catalogUnavailableReason: _catalogUnavailableReason,
          onRetryCatalogLoad: _retryCatalogLoad,
          hasSeenOnboarding: widget.hasSeenOnboarding,
        ),
      ),
    );
  }
}
