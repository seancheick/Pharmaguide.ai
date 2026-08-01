import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/data/vocab_registry.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/utils/retry.dart';
import 'package:pharmaguide/data/database/core_database.dart';
import 'package:pharmaguide/data/database/interaction_database.dart';
import 'package:pharmaguide/data/database/user_database.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/features/dev/screenshot_seeder.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';
import 'package:pharmaguide/features/history/providers/clinical_signal_lifecycle_provider.dart';
import 'package:pharmaguide/features/history/providers/health_history_providers.dart';
import 'package:pharmaguide/features/stack/providers/stack_reminder_providers.dart';
import 'package:pharmaguide/services/catalog_swap.dart';
import 'package:pharmaguide/services/catalog_updater_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';

/// SharedPreferences key for the most recently activated catalog
/// version. Persisting this means a relaunch with the same remote
/// version doesn't trigger a redundant download/swap cycle (T0.6).
const String _kCatalogVersionPrefKey = 'activeCatalogVersion';

// Phase 11.11 hygiene (2026-05-17): staged route toggles were removed
// after the route-coherence promotion proved stable. v2 is now the
// unconditional production route for Product Detail, Profile Setup,
// Medication Entry, Search, and Quick Check.
// If a future rollback is needed, restore via git revert; carrying
// the dart-define plumbing forever was creating audit noise.

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

  // Capture uncaught errors from any spawned isolate (e.g. compute()).
  // Sentry's `appRunner` zone wrap doesn't cross isolate boundaries, so
  // background work would otherwise crash invisibly.
  final isolateErrorPort = RawReceivePort((dynamic message) {
    final pair = (message as List).cast<String?>();
    final errorMsg = pair.isNotEmpty ? pair.first : null;
    final stackStr = pair.length > 1 ? pair.last : null;
    CrashReportingService().recordError(
      Exception(errorMsg ?? 'isolate-error'),
      stackStr != null ? StackTrace.fromString(stackStr) : StackTrace.current,
      fatal: true,
      hint: 'isolate:uncaught',
    );
  });
  Isolate.current.addErrorListener(isolateErrorPort.sendPort);

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
  // Cache invalidation: cached detail blobs were fetched against the
  // previous catalog snapshot and may not match the new rows'
  // detail_blob_sha256 — clear them whenever a new catalog activates.
  late final SyncService _syncService = SyncService(
    onCatalogActivated: () => widget.userDb.clearDetailCache(),
  );
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

  /// Consecutive unhealthy refresh ticks — drives the retry backoff
  /// (5m → 10m → 20m → 40m → 80m → cap 2h, ±20% jitter). Reset to 0 as
  /// soon as a catalog is available again (healthy 1h cadence).
  int _refreshFailureStreak = 0;

  /// True once a routine version-bump detection has already paid its
  /// 0-60min fleet-desync jitter — the next tick downloads immediately.
  bool _jitterApplied = false;

  final math.Random _refreshRandom = math.Random();

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
        // Boot-time promote hardening: a `.staging` left by a previous
        // process is of unknown provenance (the OS may have killed the
        // app mid-download), so revalidate before letting it replace the
        // live catalog. SyncService also refuses outright while the
        // `.staging.version` marker (= not yet validated) is present.
        await _syncService.activateStagedCoreDbIfPresent(revalidate: true);
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

    // Awaited before setState so the seeded stack entries are visible
    // on the very first build of any screen that reads from
    // userDb.getActiveStack(). The seeder early-returns instantly when
    // SCREENSHOT_MODE is false, so this adds no overhead to normal
    // builds (and the entire code path constant-folds away in release).
    if (initialDb != null) {
      await ScreenshotSeeder.maybeRun(coreDb: initialDb, userDb: widget.userDb);
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
    // Manual retry: re-checks the manifest and only downloads when a
    // new/needed version exists (no blanket force-download). When no
    // live DB is open, _refreshCatalogIfNeeded still forces the fetch.
    await _refreshCatalogIfNeeded(manual: true);
  }

  void _scheduleCatalogRefresh({Duration? initialDelay}) {
    _catalogRefreshTimer?.cancel();
    if (!widget.supabaseReady) return;

    final Duration delay;
    if (initialDelay != null) {
      delay = initialDelay;
    } else if (_catalogAvailable) {
      // Healthy: reset the failure backoff and resume the 1h cadence.
      _refreshFailureStreak = 0;
      delay = const Duration(hours: 1);
    } else {
      // Unhealthy: exponential backoff with ±20% jitter so a fleet of
      // failing clients doesn't hammer Supabase in lockstep.
      _refreshFailureStreak++;
      delay = backoffDelay(
        _refreshFailureStreak,
        base: const Duration(minutes: 5),
        cap: const Duration(hours: 2),
        random: _refreshRandom,
      );
    }

    _catalogRefreshTimer = Timer(delay, () {
      unawaited(_refreshCatalogIfNeeded());
    });
  }

  Future<void> _refreshCatalogIfNeeded({bool manual = false}) async {
    if (!widget.supabaseReady || _syncInFlight) {
      return;
    }

    _syncInFlight = true;
    Duration? nextDelayOverride;
    try {
      // Fleet de-sync: when a ROUTINE refresh tick (not first-install,
      // not a manual retry) detects a remote version bump, defer the
      // download by a random 0-60min so the whole installed base doesn't
      // download the new catalog in the same minute. First-install
      // (_coreDb == null) and manual paths stay immediate.
      if (!manual &&
          _coreDb != null &&
          _activeCatalogVersion != null &&
          !_jitterApplied) {
        final bumped = await _syncService.isUpdateAvailable(
          _activeCatalogVersion!,
        );
        if (bumped) {
          _jitterApplied = true;
          nextDelayOverride = Duration(
            minutes: _refreshRandom.nextInt(61), // 0-60 min
          );
          debugPrint(
            'Catalog version bump detected; jittering download by '
            '$nextDelayOverride to de-synchronize the fleet',
          );
          return;
        }
      }
      _jitterApplied = false;

      // D2: probe + stage logic lives in CatalogUpdaterService now.
      // The widget keeps ownership of the swap step (which mutates
      // setState and closes the previous DB) — see swap branch below.
      // `_coreDb == null` forces a download even when the remote
      // version matches `_activeCatalogVersion`: a primed-from-prefs
      // version with no live DB means we still need to fetch.
      final checkResult = await _updater.checkForUpdate(
        installedVersion: _activeCatalogVersion,
        forceDownload: _coreDb == null,
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
          // Network drop mid-download (partial .staging is kept for
          // Range-resume on the next tick) or validation failure
          // (staged file already cleaned by stageCoreDbDownload).
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
      _scheduleCatalogRefresh(initialDelay: nextDelayOverride);
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
        _showCatalogUpdatedToast(version);
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

  void _showCatalogUpdatedToast(String version) {
    PGToast.showWith(
      scaffoldMessengerKey.currentState,
      'Catalog updated to v$version',
      variant: PGToastVariant.success,
      duration: const Duration(seconds: 3),
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
        theme: V2Theme.light,
        darkTheme: V2Theme.dark,
        // Explicit: the bootstrap screen follows the device appearance too.
        themeMode: ThemeMode.system,
        home: const _BootstrapLoadingScreen(),
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
          // One always-on observer persists added/changed/resolved clinical
          // signals. It is fail-closed: partial or unavailable analysis never
          // resolves an existing event as an all-clear.
          ref.watch(clinicalSignalLifecycleProvider);
          // Device notifications are a disposable projection of the same
          // append-only Health History log. No second reminder store exists.
          ref.watch(healthReminderSyncProvider);
          // Per-item stack reminders are the same idea over the stack table:
          // a separate id namespace, rebuilt from the database, never a
          // second source of truth.
          ref.watch(stackReminderSyncProvider);
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

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(V2Spacing.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: context.v2.accent,
                  ),
                ),
                const SizedBox(height: V2Spacing.space16),
                Text(
                  'Preparing PharmaGuide',
                  style: V2Typography.titleSm(color: context.v2.fg),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: V2Spacing.space8),
                Text(
                  'Opening the verified on-device catalog.',
                  style: V2Typography.bodySm(color: context.v2.fgMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
