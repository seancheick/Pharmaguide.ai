import 'dart:async';
import 'dart:ui';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/core/data/vocab_registry.dart';
import 'package:pharmaguide/core/theme/app_theme.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';
import 'package:pharmaguide/services/analytics_service.dart';
import 'package:pharmaguide/services/catalog_swap.dart';
import 'package:pharmaguide/services/catalog_updater_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';

/// SharedPreferences key for the most recently activated catalog
/// version. Persisting this means a relaunch with the same remote
/// version doesn't trigger a redundant download/swap cycle (T0.6).
const String _kCatalogVersionPrefKey = 'activeCatalogVersion';

/// Phase 11.7g.3 staged route swap toggle. Set via:
///   `--dart-define=USE_V2_PRODUCT_DETAIL=true`
/// When true, the production `/product/:dsldId` route renders the v2
/// ConnectedScreen instead of the legacy ProductDetailScreen. Default
/// false keeps production on the legacy widget until TestFlight cycle
/// passes — see `knowledge/product-detail-v2-route-swap-readiness.md`.
const bool _useV2ProductDetail = bool.fromEnvironment(
  'USE_V2_PRODUCT_DETAIL',
  defaultValue: false,
);

/// Phase 11.7L.B staged route swap toggle for ProfileSetup. Set via:
///   `--dart-define=USE_V2_PROFILE_SETUP=true`
/// When true, the production `/profile/setup` route renders the v2
/// mirror (`ProfileSetupV2Screen`) instead of the legacy screen.
/// Logic, providers, and save semantics are identical between the two
/// — this is a pure visual swap — so flipping the flag at TestFlight
/// time is low-risk. Default false keeps production on the legacy
/// screen until Sean signs off on the v2 mirror on a real device.
const bool _useV2ProfileSetup = bool.fromEnvironment(
  'USE_V2_PROFILE_SETUP',
  defaultValue: false,
);

/// Phase 11.7L.E.1 staged route swap toggle for MedicationEntry.
/// Set via `--dart-define=USE_V2_MEDICATION_ENTRY=true`.
/// When true, the production `/medication-entry` route renders the v2
/// mirror (`MedicationEntryV2Screen`) instead of the legacy screen.
/// Engine, RxNorm API calls, and the `StackActions.addMedication`
/// payload are byte-identical between the two — a pure visual swap
/// plus the snackbar-after-pop bug fix. Default false keeps
/// production on the legacy screen until real-device verification.
const bool _useV2MedicationEntry = bool.fromEnvironment(
  'USE_V2_MEDICATION_ENTRY',
  defaultValue: false,
);

/// Phase 11.7L.E.2 staged route swap toggle for Search. Set via
/// `--dart-define=USE_V2_SEARCH=true`. When true, the production
/// `/search` route renders the v2 mirror (`SearchV2Screen`) instead
/// of the legacy screen. Same `coreDatabase.searchProducts` /
/// `filterProducts` calls, same RecentSearchesService persistence,
/// same quality filter vocabulary — the visual layer changes and
/// on-market results render first per Sean's spec. Default false.
const bool _useV2Search = bool.fromEnvironment(
  'USE_V2_SEARCH',
  defaultValue: false,
);

/// Phase 11.7L.E.3 staged route swap toggle for QuickCheck. Set via
/// `--dart-define=USE_V2_QUICK_CHECK=true`. When true, the production
/// `/quick-check` route renders the v2 mirror (`QuickCheckV2Screen`)
/// instead of the legacy "Safe to Take Together?" screen. Same pair-
/// check engine, same `runPairCheck` helper, same `InteractionResult`
/// + `Severity` enums — only the surface changes. Default false.
const bool _useV2QuickCheck = bool.fromEnvironment(
  'USE_V2_QUICK_CHECK',
  defaultValue: false,
);

const String _sentryDsn = String.fromEnvironment('SENTRY_DSN');
const String _sentryEnv = String.fromEnvironment(
  'SENTRY_ENVIRONMENT',
  defaultValue: 'development',
);
const String _sentryRelease = String.fromEnvironment('SENTRY_RELEASE');

void main() async {
  // Suppress Drift's "created multiple times" warning. We legitimately
  // instantiate `CoreDatabase` twice during bootstrap: once for the live
  // app instance (kept alive via Riverpod) and once briefly inside
  // `SyncService._validateStagedDatabase` to verify a freshly-downloaded
  // OTA file matches the version the manifest promised. The two instances
  // point to different file paths and never run queries concurrently, so
  // the warning is benign noise here.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // Bootstrap Sentry first so it wraps everything below in a Sentry zone.
  // When SENTRY_DSN is empty, this degrades to a buffer-only init and simply
  // runs [_runApp]. No-op safe.
  await CrashReportingService().bootstrap(
    dsn: _sentryDsn,
    environment: _sentryEnv,
    release: _sentryRelease,
    appRunner: _runApp,
  );
}

Future<void> _runApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Route Flutter framework errors + platform-level errors to Sentry.
  FlutterError.onError = (details) {
    CrashReportingService().recordError(
      details.exception,
      details.stack ?? StackTrace.current,
      fatal: false,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    CrashReportingService().recordError(error, stack, fatal: true);
    return true;
  };

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

  // Eager-load all 25 controlled vocabularies in parallel so render-path
  // widgets can do sync VocabRegistry.instance.verdict(id)?.name lookups
  // without FutureBuilder. Soft-fail: if a vocab asset is missing the
  // registry stays empty for that vocab and call sites fall back to
  // legacy hardcoded labels (drift contracts in test/core/ keep both
  // sources in lockstep).
  try {
    await VocabRegistry.instance.init();
  } on Object catch (e) {
    debugPrint('[vocab-registry] init failed (non-fatal): $e');
  }

  final userDb = await openUserDatabase();

  // Materialize the bundled interaction DB and open it. Soft-fail: if the
  // bundle is missing or corrupt, we still launch the app — interaction
  // checks degrade to "no curated data available" rather than blocking the
  // user from scanning products. The release-gate test
  // `bundled_interaction_db_test.dart` makes a missing bundle a build
  // failure, so we should never see this branch in shipped builds.
  InteractionDatabase? interactionDb;
  final interactionLoadStopwatch = Stopwatch()..start();
  try {
    interactionDb = await openInteractionDatabase();
    interactionLoadStopwatch.stop();
    debugPrint(
      '[interaction-db] bootstrap load: '
      '${interactionLoadStopwatch.elapsedMilliseconds}ms',
    );
  } on Object catch (e) {
    interactionLoadStopwatch.stop();
    debugPrint('[interaction-db] bootstrap failed: $e');
  }

  final hasSeenOnboarding = await OnboardingPrefs.hasSeen();

  runApp(
    PharmaGuideBootstrap(
      userDb: userDb,
      interactionDb: interactionDb,
      supabaseReady: supabaseReady,
      hasSeenOnboarding: hasSeenOnboarding,
    ),
  );
}

class PharmaGuideBootstrap extends StatefulWidget {
  final UserDatabase userDb;
  final InteractionDatabase? interactionDb;
  final bool supabaseReady;
  final bool hasSeenOnboarding;

  const PharmaGuideBootstrap({
    super.key,
    required this.userDb,
    required this.interactionDb,
    required this.supabaseReady,
    required this.hasSeenOnboarding,
  });

  @override
  State<PharmaGuideBootstrap> createState() => _PharmaGuideBootstrapState();
}

class _PharmaGuideBootstrapState extends State<PharmaGuideBootstrap> {
  final SyncService _syncService = SyncService();
  late final CatalogSwapper _swapper = CatalogSwapper.production(
    syncService: _syncService,
  );
  late final CatalogUpdaterService _updater = CatalogUpdaterService.production(
    syncService: _syncService,
  );

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
    unawaited(widget.interactionDb?.close());
    unawaited(widget.userDb.close());
    super.dispose();
  }

  Future<void> _bootstrapCatalog() async {
    CoreDatabase? initialDb;
    String? initialReason;

    // T0.6: prime _activeCatalogVersion from SharedPreferences so the
    // version guard in _refreshCatalogIfNeeded recognizes a no-op
    // refresh on relaunch (same remote version → skip download). The
    // value is overwritten by validateCatalogSnapshot() once the DB
    // actually opens, so a stale prefs entry can't cause us to skip
    // legitimate updates — it only affects the very first refresh tick.
    _activeCatalogVersion = await _restoreActiveCatalogVersion();

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
      initialReason = _unavailableReason(
        includeRetryHint: widget.supabaseReady,
      );
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
        initialDelay ??
        (_catalogAvailable
            ? const Duration(hours: 1)
            : const Duration(minutes: 5));

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
      // D2: probe + stage logic lives in CatalogUpdaterService now.
      // The widget keeps ownership of the swap step (which mutates
      // setState and closes the previous DB) — see swap branch below.
      // `_coreDb == null` forces a download even when the remote
      // version matches `_activeCatalogVersion`: a primed-from-prefs
      // version with no live DB means we still need to fetch.
      final checkResult = await _updater.checkForUpdate(
        installedVersion: _activeCatalogVersion,
        forceDownload: forceDownload || _coreDb == null,
      );

      switch (checkResult) {
        case CatalogUpToDate():
          return;
        case CatalogUnreachable(:final error):
          // Two sub-cases under one variant:
          //   error == null → probe returned no row (legit "no
          //                   manifest yet" / first-push state).
          //                   Match pre-D2 behavior: silent return,
          //                   no UI flip — even if `_coreDb == null`,
          //                   the bundled-asset bootstrap path
          //                   handles that downstream.
          //   error != null → probe threw (network/RPC failure).
          //                   Flip the "catalog unavailable" UI iff
          //                   we have nothing to fall back on.
          if (error != null) {
            debugPrint('Catalog probe failed: $error');
            if (mounted && _coreDb == null) {
              setState(() {
                _catalogAvailable = false;
                _catalogUnavailableReason = _unavailableReason(
                  includeRetryHint: true,
                );
              });
            }
          }
          return;
        case CatalogStageFailed(:final reason):
          // Network drop mid-download or sha mismatch. Partial file
          // is already cleaned by SyncService.stageCoreDbDownload.
          debugPrint('Catalog stage failed: $reason');
          if (mounted && _coreDb == null) {
            setState(() {
              _catalogAvailable = false;
              _catalogUnavailableReason = _unavailableReason(
                includeRetryHint: true,
              );
            });
          }
          return;
        case CatalogStaged(:final version):
          // Bundle validated and waiting in `*.staging`. Fall through
          // to the swap routine below.
          await _activateStagedCatalog(downloadedVersion: version);
      }
    } finally {
      _syncInFlight = false;
      _scheduleCatalogRefresh();
    }
  }

  /// Activate a freshly-staged catalog file in-session.
  ///
  /// Spec: T0.6 / Track D D3. The validation gate inside
  /// `_validateStagedDatabase` has already cleared the file by the
  /// time `CatalogUpdaterService` returns [CatalogStaged]; the swap
  /// routine adds a second-line defense by closing the new DB on a
  /// validation failure during open.
  Future<void> _activateStagedCatalog({
    required String downloadedVersion,
  }) async {
    final swapResult = await _swapper.swap();

    switch (swapResult) {
      case SwapSuccess(:final newDb, :final version):
        if (!mounted) {
          await newDb.close();
          return;
        }
        final oldDb = _coreDb;
        setState(() {
          _coreDb = newDb;
          _activeCatalogVersion = version;
          _catalogAvailable = true;
          _catalogUnavailableReason = null;
          _scopeVersion++;
        });
        unawaited(_persistActiveCatalogVersion(version));
        unawaited(oldDb?.close());
        _showCatalogUpdatedSnackbar(version);
      case SwapRolledBack(:final reason):
        debugPrint('Catalog swap rolled back: $reason');
      case SwapNoStaging():
        debugPrint(
          'Catalog swap: no staging file present after download '
          'returned $downloadedVersion',
        );
    }
  }

  /// Persist the activated catalog version so the next launch's
  /// version guard can short-circuit a redundant download when the
  /// remote hasn't changed.
  Future<void> _persistActiveCatalogVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCatalogVersionPrefKey, version);
    } on Object catch (e) {
      debugPrint('Catalog version persistence failed: $e');
    }
  }

  Future<String?> _restoreActiveCatalogVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kCatalogVersionPrefKey);
    } on Object catch (e) {
      debugPrint('Catalog version restore failed: $e');
      return null;
    }
  }

  void _showCatalogUpdatedSnackbar(String version) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Catalog updated to v$version'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return ProviderScope(
      key: ValueKey(_scopeVersion),
      overrides: [
        userDatabaseProvider.overrideWithValue(widget.userDb),
        if (_coreDb != null) coreDatabaseProvider.overrideWithValue(_coreDb!),
        if (widget.interactionDb != null)
          interactionDatabaseProvider.overrideWithValue(widget.interactionDb!),
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
          useV2ProductDetail: _useV2ProductDetail,
          useV2ProfileSetup: _useV2ProfileSetup,
          useV2MedicationEntry: _useV2MedicationEntry,
          useV2Search: _useV2Search,
          useV2QuickCheck: _useV2QuickCheck,
        ),
      ),
    );
  }
}
