import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pharmaguide/app.dart';
import 'package:pharmaguide/core/components/pg_toast.dart';
import 'package:pharmaguide/core/data/vocab_registry.dart';
import 'package:pharmaguide/core/navigation/root_navigator_key.dart';
import 'package:pharmaguide/core/navigation/launch_link_buffer.dart';
import 'package:pharmaguide/core/theme/reduce_transparency.dart';
import 'package:pharmaguide/core/theme/v2/v2_palette.dart';
import 'package:pharmaguide/core/theme/v2/v2_spacing.dart';
import 'package:pharmaguide/core/theme/v2/v2_theme.dart';
import 'package:pharmaguide/core/theme/v2/v2_typography.dart';
import 'package:pharmaguide/core/utils/retry.dart';
import 'package:pharmaguide/data/providers/database_providers.dart';
import 'package:pharmaguide/data/supabase/supabase_client.dart';
import 'package:pharmaguide/data/providers/detail_blob_provider.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';
import 'package:pharmaguide/features/dev/screenshot_seeder.dart';
import 'package:pharmaguide/features/settings/providers/app_preferences_provider.dart';
import 'package:pharmaguide/features/ai_share/ai_share_snapshot_pusher.dart';
import 'package:pharmaguide/features/settings/v2/guest_data_question_screen.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';
import 'package:pharmaguide/features/history/providers/clinical_signal_lifecycle_provider.dart';
import 'package:pharmaguide/features/history/providers/health_history_providers.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_alert_providers.dart';
import 'package:pharmaguide/features/safety_alerts/providers/safety_push_provider.dart';
import 'package:pharmaguide/features/stack/providers/active_stack_provider.dart';
import 'package:pharmaguide/features/stack/providers/stack_reminder_providers.dart';
import 'package:pharmaguide/services/catalog_updater_service.dart';
import 'package:pharmaguide/services/release_store.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:pharmaguide/services/onboarding_prefs.dart';
import 'package:pharmaguide/services/settings/app_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pharmaguide/core/components/pg_empty_state.dart';
import 'package:pharmaguide/services/auth/account_storage.dart';
import 'package:pharmaguide/services/auth/pg_auth_service.dart';
import 'package:pharmaguide/services/product_submission_draft_store.dart';
import 'package:pharmaguide/services/sharing/ai_share_prefs_store.dart';

/// SharedPreferences key for the active catalog version, which tags Sentry
/// events (crash_reporting_service.dart).
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
  // Claim links from the first moment: the awaited setup below runs before
  // any widget exists, and a link landing then had no handler at all.
  final launchLinks = LaunchLinkBuffer()..attach();
  V2Typography.useBundledFontsOnly();
  unawaited(ReduceTransparency.listen());

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

  final accountGuard = AccountSwitchGuard.production(
    openDatabase: openUserDatabase,
    readSessionUid: _launchSessionUid,
    onOwnerChange: _endOutgoingOwnerWork,
    onNotificationCleanup: _cancelAccountNotifications,
    onAccountRemoved: (uid) async =>
        (await ProductSubmissionDraftStore.open()).deleteAccount(uid),
  );
  await accountGuard.boot(sessionUid: _launchSessionUid());

  final hasSeenOnboarding = await OnboardingPrefs.hasSeen();

  final appPreferencesStore = SharedPreferencesAsyncAppPreferencesStore(
    SharedPreferencesAsync(),
  );
  final appPreferencesRepository = AppPreferencesRepository(
    appPreferencesStore,
  );
  final appPreferencesController = AppPreferencesController(
    repository: appPreferencesRepository,
    initialPreferences: await appPreferencesRepository.load(),
  );

  try {
    runApp(
      PharmaGuideBootstrap(
        accountGuard: accountGuard,
        supabaseReady: supabaseReady,
        hasSeenOnboarding: hasSeenOnboarding,
        appPreferencesController: appPreferencesController,
        launchLinks: launchLinks,
      ),
    );
  } on Object {
    appPreferencesController.dispose();
    rethrow;
  }
}

/// The session this launch starts with. Null in guest and placeholder builds.
String? _launchSessionUid() {
  try {
    return supabase.auth.currentUser?.id;
  } on Object {
    return null;
  }
}

/// Cancel OS writes without changing the active owner's account preferences.
Future<void> _cancelAccountNotifications() async {
  await FlutterLocalNotificationsPlugin().cancelAll();
}

/// Clear outgoing-owner state; the new tree schedules its own reminders.
Future<void> _endOutgoingOwnerWork() async {
  await Future.wait([
    Future.sync(_cancelAccountNotifications),
    Future.sync(
      () => AiSharePrefsStore(
        SharedPreferencesAsyncAppPreferencesStore(),
      ).clear(),
    ),
  ]);
}

class PharmaGuideBootstrap extends StatefulWidget {
  final AccountSwitchGuard accountGuard;
  final bool supabaseReady;
  final bool hasSeenOnboarding;
  final AppPreferencesController appPreferencesController;

  /// Attached in `_runApp` before any setup; released once the router mounts.
  final LaunchLinkBuffer launchLinks;

  const PharmaGuideBootstrap({
    super.key,
    required this.accountGuard,
    required this.supabaseReady,
    required this.hasSeenOnboarding,
    required this.appPreferencesController,
    required this.launchLinks,
  });

  @override
  State<PharmaGuideBootstrap> createState() => _PharmaGuideBootstrapState();
}

class _PharmaGuideBootstrapState extends State<PharmaGuideBootstrap> {
  late final SyncService _syncService = SyncService();
  ReleaseStore? _store;
  CatalogUpdaterService? _updater;

  /// The open release. A replaced one stays open until the process ends, so a
  /// check that was already running can always finish (ADR-012).
  ReleaseGeneration? _generation;
  final List<ReleaseGeneration> _retired = [];
  String? _catalogUnavailableReason;
  bool _catalogAvailable = false;
  bool _bootstrapped = false;
  bool _syncInFlight = false;
  bool _accountSwitching = false;
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

  LaunchLinkBuffer get _launchLinks => widget.launchLinks;

  /// Read once when the router is first built; the router owns links after.
  String? _launchLocation;

  @override
  void initState() {
    super.initState();
    widget.accountGuard.releaseConsumers = _releaseAccountConsumers;
    widget.accountGuard.onChanged = _onAccountChanged;
    widget.accountGuard.onGuestDataQuestion = _onGuestDataQuestion;
    unawaited(_bootstrapCatalog());
  }

  @override
  void dispose() {
    _launchLinks.detach();
    _catalogRefreshTimer?.cancel();
    unawaited(_generation?.close());
    for (final retired in _retired) {
      unawaited(retired.close());
    }
    unawaited(widget.accountGuard.close());
    widget.appPreferencesController.dispose();
    super.dispose();
  }

  /// Removing the tree disposes its providers, listeners and timers. Frames
  /// stop in the background, and the switch must not wait for the next launch.
  Future<void> _releaseAccountConsumers() async {
    if (!mounted) return;
    setState(() => _accountSwitching = true);
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
  }

  void _onAccountChanged() {
    if (!mounted) return;
    setState(() {
      _accountSwitching = false;
      _scopeVersion++;
    });
    returnHomeAfterAccountChange();
  }

  void _onGuestDataQuestion() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrapCatalog() async {
    ReleaseGeneration? initial;
    try {
      final store = ReleaseStore(
        documents: await getApplicationDocumentsDirectory(),
      );
      _store = store;
      _updater = CatalogUpdaterService.production(
        store: store,
        syncService: _syncService,
      );
      initial = await store.open();
      debugPrint('[release] active ${initial.record.id}');
    } on Object catch (e) {
      debugPrint('Local/bundled catalog unavailable: $e');
    }
    final initialDb = initial?.core;

    if (!mounted) {
      await initial?.close();
      return;
    }

    // Awaited before setState so the seeded stack entries are visible
    // on the very first build of any screen that reads from
    // userDb.getActiveStack(). The seeder early-returns instantly when
    // SCREENSHOT_MODE is false, so this adds no overhead to normal
    // builds (and the entire code path constant-folds away in release).
    if (initialDb != null) {
      final userDb = widget.accountGuard.database;
      if (userDb != null) {
        await ScreenshotSeeder.maybeRun(coreDb: initialDb, userDb: userDb);
      }
    }

    setState(() {
      _generation = initial;
      _catalogAvailable = initial != null;
      _catalogUnavailableReason = initial == null
          ? _unavailableReason(includeRetryHint: widget.supabaseReady)
          : null;
      _launchLocation = _launchLinks.takeLocation();
      _bootstrapped = true;
      _scopeVersion++;
    });
    // The app router mounts on this frame. Keep claiming links until it has,
    // then hand it any link that landed in between.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _launchLinks.detach();
      final late = _launchLinks.takeLocation();
      final routerContext = rootNavigatorKey.currentContext;
      if (late != null && routerContext != null) {
        GoRouter.of(routerContext).go(late);
      }
    });

    if (initial != null) {
      unawaited(_persistActiveCatalogVersion(initial.record.catalogVersion));
    }
    _scheduleCatalogRefresh(
      // With no catalog at all there is nothing to de-synchronize.
      initialDelay: initial == null
          ? Duration.zero
          : const Duration(seconds: 10),
    );
  }

  Future<void> _retryCatalogLoad() async {
    // Manual retry: re-checks the manifest and only downloads when a
    // new/needed version exists (no blanket force-download). When no
    // release is open, _refreshCatalogIfNeeded still forces the fetch.
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
    final store = _store;
    final updater = _updater;
    if (!widget.supabaseReady ||
        _syncInFlight ||
        store == null ||
        updater == null) {
      return;
    }
    if (_accountSwitching) {
      _scheduleCatalogRefresh();
      return;
    }

    _syncInFlight = true;
    Duration? nextDelayOverride;
    try {
      final installed = InstalledRelease.of(store);
      final check = await updater.checkForUpdate(
        installed: installed,
        // With no open release, take the current one whatever its version.
        forceDownload: _generation == null,
        onVerified: (manifest) => store.recordVerified(
          sequence: manifest.sequence,
          blockedCatalog: manifest.blockedCatalog,
          blockedRules: manifest.blockedRules,
        ),
      );

      switch (check) {
        case CatalogUpToDate():
          _jitterApplied = false;
        case CatalogUnreachable(:final error):
          // error == null means the probe found no row (legit first-push
          // state), which changes nothing on screen.
          if (error != null) {
            debugPrint('Catalog probe failed: $error');
            _showUnavailableIfNoRelease();
          }
        case CatalogRefused(:final reason):
          debugPrint('Catalog release refused: $reason');
          _showUnavailableIfNoRelease();
        case CatalogUpdateFound():
          // Fleet de-sync: a ROUTINE tick defers the download by a random
          // 0-60min so the whole installed base doesn't download in the same
          // minute. First install, manual and blocked-version paths don't wait.
          if (!manual &&
              _generation != null &&
              !_jitterApplied &&
              !check.isUrgentFor(InstalledRelease.of(store))) {
            _jitterApplied = true;
            nextDelayOverride = Duration(
              minutes: _refreshRandom.nextInt(61), // 0-60 min
            );
            debugPrint(
              'Release update found; jittering download by '
              '$nextDelayOverride to de-synchronize the fleet',
            );
            return;
          }
          _jitterApplied = false;
          await _stageAndActivate(store, updater, check, installed);
        case CatalogStaged() || CatalogStageFailed():
          // Only stage() returns these.
          break;
      }
      await _settleBlockedRelease(store);
    } finally {
      _syncInFlight = false;
      _scheduleCatalogRefresh(initialDelay: nextDelayOverride);
    }
  }

  Future<void> _stageAndActivate(
    ReleaseStore store,
    CatalogUpdaterService updater,
    CatalogUpdateFound found,
    InstalledRelease installed,
  ) async {
    final staged = await updater.stage(found, installed: installed);
    switch (staged) {
      case CatalogStaged(:final candidate):
        final userDb = widget.accountGuard.database;
        final result = await store.activate(
          candidate,
          stackData: userDb == null
              ? null
              : (catalog) => fetchStackDetailForRelease(
                  candidate: catalog,
                  userDb: userDb,
                  service: DetailBlobService(),
                ),
        );
        switch (result) {
          case ReleaseActivated(:final generation):
            if (await _adoptRelease(generation)) {
              _showCatalogUpdatedToast(generation.record.catalogVersion);
            }
          case ReleaseNotActivated(:final reason):
            // The phone stays on its release. Nothing it has open moved.
            debugPrint('Release not activated: $reason');
            _showUnavailableIfNoRelease();
        }
      case CatalogStageFailed(:final reason):
        // Network drop mid-download (the partial is kept for Range-resume) or a
        // file that failed validation (already deleted).
        debugPrint('Catalog stage failed: $reason');
        _showUnavailableIfNoRelease();
      default:
        break;
    }
  }

  /// A verified manifest named a version this phone uses, and no replacement
  /// arrived. Selecting again returns to the previous release if it can, or
  /// withholds only the affected assessment.
  Future<void> _settleBlockedRelease(ReleaseStore store) async {
    final generation = _generation;
    if (generation == null || store.isSettled(generation)) return;
    try {
      final next = await store.reselect();
      // Nothing could change yet, such as on a full disk. Rebuilding the app
      // would only reset the screen; the next tick tries again.
      if (next.record.id == generation.record.id &&
          next.rulesWithheld == generation.rulesWithheld) {
        await next.close();
        return;
      }
      await _adoptRelease(next);
    } on Object catch (e) {
      debugPrint('Release reselection failed: $e');
    }
  }

  void _showUnavailableIfNoRelease() {
    if (!mounted || _generation != null) return;
    setState(() {
      _catalogAvailable = false;
      _catalogUnavailableReason = _unavailableReason(includeRetryHint: true);
    });
  }

  /// Moves the app onto [generation] with one rebuild, so both databases change
  /// together and no restart is needed. Returns false (closing it) when the app
  /// is no longer mounted.
  Future<bool> _adoptRelease(ReleaseGeneration generation) async {
    if (!mounted) {
      await generation.close();
      return false;
    }
    final old = _generation;
    setState(() {
      _generation = generation;
      _catalogAvailable = true;
      _catalogUnavailableReason = null;
      _scopeVersion++;
    });
    if (old != null) _retired.add(old);
    unawaited(_persistActiveCatalogVersion(generation.record.catalogVersion));
    return true;
  }

  /// Persist the active catalog version for the Sentry tag.
  Future<void> _persistActiveCatalogVersion(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCatalogVersionPrefKey, version);
    } on Object catch (e) {
      debugPrint('Catalog version persistence failed: $e');
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
    final userDb = widget.accountGuard.database;
    if (widget.accountGuard.awaitingGuestDataAnswer) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: V2Theme.light,
        darkTheme: V2Theme.dark,
        themeMode: widget.appPreferencesController.preferences.theme.themeMode,
        home: GuestDataQuestionScreen(
          onAnswer: widget.accountGuard.answerGuestDataQuestion,
        ),
      );
    }
    if (_bootstrapped && !_accountSwitching && userDb == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: V2Theme.light,
        darkTheme: V2Theme.dark,
        themeMode: widget.appPreferencesController.preferences.theme.themeMode,
        home: _UserDataUnavailableScreen(onRetry: widget.accountGuard.retry),
      );
    }
    if (!_bootstrapped || _accountSwitching || userDb == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: V2Theme.light,
        darkTheme: V2Theme.dark,
        // AppThemePreference.system still resolves to ThemeMode.system.
        themeMode: widget.appPreferencesController.preferences.theme.themeMode,
        home: const _BootstrapLoadingScreen(),
      );
    }

    return ProviderScope(
      key: ValueKey(_scopeVersion),
      overrides: [
        appPreferencesControllerProvider.overrideWith(
          (_) => widget.appPreferencesController,
          disposeNotifier: false,
        ),
        userDatabaseProvider.overrideWithValue(userDb),
        activeAccountProvider.overrideWithValue(widget.accountGuard.account),
        accountSwitchGuardProvider.overrideWithValue(widget.accountGuard),
        if (_generation case final generation?) ...[
          coreDatabaseProvider.overrideWithValue(generation.core),
          if (generation.rules case final rules?)
            interactionDatabaseProvider.overrideWithValue(rules),
        ],
      ],
      // Register the stack sync auto-listener as soon as the ProviderScope
      // mounts. The Consumer reads [stackSyncListenerProvider] once; the
      // provider itself calls `ref.keepAlive()` so its auth + connectivity
      // subscriptions survive disposal of this Consumer.
      child: Consumer(
        builder: (context, ref, child) {
          ref.watch(stackSyncListenerProvider);
          // Keeps the stack's product detail ready for offline checks.
          ref.watch(stackDetailReadyProvider);
          // Opt-in AI-share refresh (ADR-009). Off for every connection until
          // the user switches it on; never runs for guests.
          ref.watch(aiShareSnapshotListenerProvider);
          // One always-on observer persists added/changed/resolved clinical
          // signals. It is fail-closed: partial or unavailable analysis never
          // resolves an existing event as an all-clear.
          ref.watch(clinicalSignalLifecycleProvider);
          // Launch, resume and reconnect each re-check the verified feed.
          ref.watch(safetyAlertRefreshProvider);
          // FCM is only a generic nudge. The handler invalidates the verified
          // feed provider, which re-fetches before any copy reaches the user.
          ref.watch(safetyPushBootstrapProvider);
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
          launchLocation: _launchLocation,
        ),
      ),
    );
  }
}

/// The owner's data didn't open. An empty database here would read as having no
/// medications, so the app waits rather than showing anything.
class _UserDataUnavailableScreen extends StatelessWidget {
  const _UserDataUnavailableScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: PGEmptyState(
            icon: Icons.lock_outline_rounded,
            eyebrow: 'Your health data',
            headline: "Your health data didn't open",
            body:
                'Nothing on this phone has changed. Please try again. Until it '
                'opens, PharmaGuide can\'t check your medications.',
            primaryLabel: 'Try again',
            primaryIcon: Icons.refresh_rounded,
            onPrimaryTap: onRetry,
          ),
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
