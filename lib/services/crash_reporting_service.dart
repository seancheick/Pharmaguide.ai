import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Crash reporting facade for PharmaGuide (Sentry-backed).
///
/// Privacy rules (medical-grade app):
///   * `sendDefaultPii` is OFF — no device identifiers or IPs attached.
///   * User health data (stack contents, ingredients, conditions, medications)
///     is NEVER forwarded. Only an opaque `userId` is sent for correlation.
///   * `beforeSend` + `beforeBreadcrumb` scrub request bodies, tags, and
///     extras for known sensitive keys before events leave the device.
///
/// The SDK is initialized in [bootstrap]. If no DSN is provided via
/// `--dart-define=SENTRY_DSN=…`, the service degrades to an in-memory buffer —
/// safe to call everywhere, never throws.
class CrashReportingService {
  static final CrashReportingService _instance = CrashReportingService._();
  factory CrashReportingService() => _instance;
  CrashReportingService._();

  static const int _breadcrumbMax = 100;
  static const int _errorMax = 50;

  static const Set<String> _sensitiveKeys = {
    'email',
    'password',
    'token',
    'auth',
    'authorization',
    'api_key',
    'apikey',
    'supabase_anon_key',
    'gemini_api_key',
    'sentry_dsn',
    'access_token',
    'refresh_token',
    'health',
    'medication',
    'medications',
    'condition',
    'conditions',
    'ingredient',
    'ingredients',
    'stack',
    'profile',
    'dob',
    'birthdate',
  };

  final List<CrashBreadcrumb> _breadcrumbBuffer = <CrashBreadcrumb>[];
  final List<RecordedCrashError> _errorBuffer = <RecordedCrashError>[];

  bool _initialized = false;
  bool _sentryEnabled = false;
  bool get isInitialized => _initialized;
  bool get isSentryEnabled => _sentryEnabled;

  List<CrashBreadcrumb> get breadcrumbs => List.unmodifiable(_breadcrumbBuffer);
  List<RecordedCrashError> get recordedErrors =>
      List.unmodifiable(_errorBuffer);

  /// Buffer-only init — used by tests and code paths that skip [bootstrap].
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (kDebugMode) {
      debugPrint('CrashReportingService initialized (buffer-only)');
    }
  }

  /// Bootstrap Sentry and run [appRunner] inside the Sentry zone so uncaught
  /// async errors are captured. Empty [dsn] → buffer-only, still runs the app.
  Future<void> bootstrap({
    required String dsn,
    required String environment,
    required String release,
    required Future<void> Function() appRunner,
  }) async {
    if (dsn.isEmpty) {
      await initialize();
      await appRunner();
      return;
    }

    await SentryFlutter.init((options) {
      options.dsn = dsn;
      options.environment = environment.isEmpty ? 'production' : environment;
      if (release.isNotEmpty) options.release = release;
      options.sendDefaultPii = false;
      options.attachStacktrace = true;
      options.attachThreads = true;
      options.enableAutoSessionTracking = true;
      options.debug = kDebugMode;
      // Beta diagnostic window: capture 100% of performance traces for full
      // visibility into slow screens / queries / network spans. This is the
      // *performance* sampler only — error & crash capture is governed by
      // options.sampleRate (unset → 100%), so bug awareness is unaffected by
      // this value either way.
      // ponytail: Sentry bills on transaction volume — drop release back to
      // ~0.2 once beta closes and real-user traffic ramps.
      options.tracesSampleRate = 1.0;
      // CPU flame-graph profiling for the beta window. Relative to
      // tracesSampleRate (ratio of profiled traces out of sampled ones), so
      // 1.0 here = profile every trace we capture. iOS/macOS only — a no-op on
      // Android, which is fine since the beta ships via iOS TestFlight.
      // ponytail: drop alongside tracesSampleRate post-beta — profiling adds
      // runtime sampling overhead. profilesSampleRate is a documented Sentry
      // API, just not yet marked stable in the 9.x SDK — hence the ignore.
      // ignore: experimental_member_use
      options.profilesSampleRate = 1.0;
      options.beforeSend = _scrubEvent;
      // Feedback events (type:'feedback') run beforeSendFeedback when set,
      // otherwise fall through to beforeSend. Wire it explicitly so the scrub
      // still applies if beforeSend is ever changed, and so the feedback
      // contact-field drop in _scrubEvent always runs on this path.
      options.beforeSendFeedback = _scrubEvent;
      options.beforeBreadcrumb = _scrubBreadcrumb;
    }, appRunner: appRunner);

    _sentryEnabled = true;
    _initialized = true;
    if (kDebugMode) {
      debugPrint(
        'CrashReportingService initialized (Sentry enabled, env=$environment)',
      );
    }
  }

  /// [hint] is an opaque surface tag like `catalog_swap:backup_failed`. When
  /// set it is attached to the Sentry event as `pg.surface=<hint>` so the
  /// dashboard can filter/group by failure surface. Safe to omit.
  void recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? hint,
  }) {
    _errorBuffer.add(
      RecordedCrashError(error.toString(), stackTrace, fatal, hint),
    );
    if (_errorBuffer.length > _errorMax) {
      _errorBuffer.removeRange(0, _errorBuffer.length - _errorMax);
    }
    if (kDebugMode) {
      final hintSuffix = hint != null ? ' [$hint]' : '';
      debugPrint(
        'CrashReport: ${fatal ? "FATAL" : "non-fatal"}$hintSuffix — $error',
      );
    }
    if (_sentryEnabled) {
      unawaited(
        Sentry.captureException(
          error,
          stackTrace: stackTrace,
          hint: fatal ? Hint.withMap({'fatal': true}) : null,
          withScope: hint == null
              ? null
              : (scope) => scope.setTag('pg.surface', hint),
        ),
      );
    }
  }

  /// Only an opaque id is sent — never email, never profile data.
  ///
  /// **Privacy note — do NOT call this with the Supabase auth user ID.**
  /// The Supabase user UUID is the foreign key to every health-related
  /// record on the Supabase side; pushing it to Sentry would create a
  /// join from a crash event back to the user's health data, which
  /// violates the spirit of the no_health_in_supabase invariant.
  ///
  /// Currently this method is intentionally never called — Sentry's
  /// SDK auto-assigns an anonymous per-install UUID for crash grouping,
  /// which is the right level of stable identity. If we ever need
  /// authenticated user context (e.g. to triage a single user's
  /// recurring bug), pass an opaque salted hash of the Supabase UUID,
  /// not the UUID itself, so Sentry cannot be joined back to the DB.
  void setUserId(String? userId) {
    _breadcrumbBuffer.add(CrashBreadcrumb('user_id=$userId'));
    _trimBreadcrumbs();
    if (kDebugMode) debugPrint('CrashReport: userId=$userId');
    if (_sentryEnabled) {
      // configureScope returns FutureOr<void>; wrap to ignore result.
      Future<void>.sync(() async {
        await Sentry.configureScope((scope) {
          if (userId == null) {
            scope.setUser(null);
          } else {
            scope.setUser(SentryUser(id: userId));
          }
        });
      });
    }
  }

  /// Outcome of the most recent scan attempt: `found`, `not_found`, or
  /// `error`. Lets Sentry triage slice events by scan path without
  /// needing the UPC or product id (which we never send).
  void setScanResult(String result) {
    if (!_sentryEnabled) return;
    Future<void>.sync(() async {
      await Sentry.configureScope(
        (scope) => scope.setTag('scan_result', result),
      );
    });
  }

  /// Coarse authentication mode: `guest` or `signedIn`. Enum-level only —
  /// never the Supabase user UUID. Lets Sentry filter "guest-only" vs.
  /// "signed-in-only" failure modes without breaking the no-PII rule.
  void setAuthState(String state) {
    if (!_sentryEnabled) return;
    Future<void>.sync(() async {
      await Sentry.configureScope((scope) => scope.setTag('auth_state', state));
    });
  }

  // ───────── Beta feedback ─────────

  /// Sends structured beta feedback to Sentry as a `type:'feedback'` event.
  ///
  /// **PHI rule:** this method accepts ONLY enum inputs and synthesizes the
  /// message itself, so no free-text/prose can reach Sentry. Users who want to
  /// add prose are routed to the Settings → Contact-support mailto, which lands
  /// in our own inbox rather than a third-party processor. The synthesized
  /// message and tags are PHI-free by construction; `_scrubEvent` (wired as
  /// `beforeSendFeedback`) drops any contact fields as a backstop.
  ///
  /// `auth_state`, `environment`, and `release` already ride on the event from
  /// the global scope/options, so they are not re-set here.
  Future<PgFeedbackSubmissionResult> captureBetaFeedback({
    required PgFeedbackCategory category,
    required PgFeedbackImpact impact,
  }) async {
    final message = _feedbackMessage(category, impact);
    _breadcrumbBuffer.add(
      CrashBreadcrumb('beta_feedback: ${category.tag}/${impact.tag}'),
    );
    _trimBreadcrumbs();
    if (kDebugMode) debugPrint('CrashReport: $message');
    if (!_sentryEnabled) return PgFeedbackSubmissionResult.disabled;

    final tags = buildFeedbackTags(
      category: category,
      impact: impact,
      catalogVersion: await _readCatalogVersion(),
    );
    try {
      await Sentry.captureFeedback(
        SentryFeedback(message: message),
        withScope: (scope) => tags.forEach(scope.setTag),
      );
      return PgFeedbackSubmissionResult.sent;
    } on Object catch (error, stackTrace) {
      recordError(
        error,
        stackTrace,
        fatal: false,
        hint: 'beta_feedback:capture_failed',
      );
      return PgFeedbackSubmissionResult.failed;
    }
  }

  static String _feedbackMessage(
    PgFeedbackCategory category,
    PgFeedbackImpact impact,
  ) => 'Beta feedback: ${category.label} / ${impact.label}';

  @visibleForTesting
  static String feedbackMessageForTest(
    PgFeedbackCategory category,
    PgFeedbackImpact impact,
  ) => _feedbackMessage(category, impact);

  /// Safe, structured tags for a beta-feedback event. Pure and side-effect
  /// free so it is exhaustively unit-tested: it accepts only enum/version
  /// inputs, so it cannot carry profile, stack, medication, or free-text data.
  @visibleForTesting
  static Map<String, String> buildFeedbackTags({
    required PgFeedbackCategory category,
    required PgFeedbackImpact impact,
    String? catalogVersion,
  }) {
    return {
      'pg.kind': 'beta_feedback',
      'feedback.category': category.tag,
      'feedback.impact': impact.tag,
      if (catalogVersion != null && catalogVersion.isNotEmpty)
        'pg.catalog_version': catalogVersion,
    };
  }

  /// Reads the active OTA catalog version for the `pg.catalog_version` tag.
  /// Mirrors main.dart's `_kCatalogVersionPrefKey`.
  // ponytail: one duplicated prefs-key literal; not worth a shared module.
  Future<String?> _readCatalogVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('activeCatalogVersion');
    } on Object catch (_) {
      return null;
    }
  }

  void log(String message) {
    _breadcrumbBuffer.add(CrashBreadcrumb(message));
    _trimBreadcrumbs();
    if (kDebugMode) debugPrint('CrashReport: $message');
    if (_sentryEnabled) {
      Sentry.addBreadcrumb(
        Breadcrumb(message: message, level: SentryLevel.info),
      );
    }
  }

  void _trimBreadcrumbs() {
    if (_breadcrumbBuffer.length > _breadcrumbMax) {
      _breadcrumbBuffer.removeRange(
        0,
        _breadcrumbBuffer.length - _breadcrumbMax,
      );
    }
  }

  // ───────── PII scrubbing ─────────

  /// True when [key] names a sensitive field. Match shape (snake_case,
  /// the convention used by every Sentry tag/context key in this app):
  ///
  ///   * exact match            (`email`, `token`)
  ///   * suffix on `_` boundary (`user_email`, `request_token`)
  ///   * middle on `_` boundary (`user_email_v2`, `access_token_v3`)
  ///
  /// Prefix matching (`<sensitive>_<descriptor>`) is intentionally NOT
  /// applied — it would catch metadata keys like `email_verified` (a
  /// bool), `ingredient_count` (an int), `stack_added_at` (a timestamp),
  /// `medication_form` (a generic enum like "tablet"/"capsule"). Those
  /// keys carry triage value without leaking PII; scrubbing them strips
  /// context the routine needs to filter Sentry events by surface.
  ///
  /// Previously this used a substring `contains` check which over-
  /// scrubbed every key embedding a sensitive token. Word-boundary
  /// matching preserves the harmless metadata keys above.
  static bool _isSensitive(String key) {
    final lower = key.toLowerCase();
    for (final sensitive in _sensitiveKeys) {
      if (lower == sensitive ||
          lower.endsWith('_$sensitive') ||
          lower.contains('_${sensitive}_')) {
        return true;
      }
    }
    return false;
  }

  @visibleForTesting
  static bool isSensitiveForTest(String key) => _isSensitive(key);

  static Map<String, dynamic> _scrubMap(Map<String, dynamic> src) {
    final out = <String, dynamic>{};
    src.forEach((k, v) {
      if (_isSensitive(k)) {
        out[k] = '[scrubbed]';
      } else if (v is Map<String, dynamic>) {
        out[k] = _scrubMap(v);
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  /// Framework debug-only asserts that only fire in `--debug` builds and
  /// never reach release/TestFlight users. They polluted Sentry with
  /// hundreds of duplicates from dev runs — drop at source so the live
  /// signal isn't drowned out. Match against the event message because
  /// the assertion text is stable across Flutter versions but the
  /// stacktrace top-frame line number is not.
  static const List<String> _debugOnlyFrameworkAsserts = [
    "'!semantics.parentDataDirty'", // 444× — debug semantics pass
    'A RenderFlex overflowed by', // 77× — debug overflow guide
    'SliverGeometry is not valid', // 5×/5× — debug sliver validator
  ];

  /// Offline is a normal state for this offline-first app. Pure
  /// network-unavailability errors (DNS failure, unreachable network)
  /// are operational noise, not crashes — drop them at source so the
  /// Sentry dashboard stays focused on real defects. Fatal events are
  /// NEVER dropped: a crash that merely *mentions* a network error
  /// still needs triage.
  ///
  /// Matched shapes (all from `dart:io` / `package:http`):
  ///   * `OSError` errno 8 (nodename nor servname provided), 50/51
  ///     (network down/unreachable), 65 (no route to host)
  ///   * `SocketException` with "Failed host lookup" /
  ///     "Network is unreachable"
  ///   * `ClientException` wrapping either of the above
  ///   * `AuthRetryableFetchException` — Supabase GoTrue's auto-refresh
  ///     timer wraps the offline socket failure in this type while the
  ///     app is backgrounded/offline (Sentry PHARMAGUIDE-18). The wrapped
  ///     message normally still carries the inner socket text, but listing
  ///     the type keeps the match robust if that wrapper text ever changes.
  ///     The offline-fragment/errno gate below still applies, so genuine
  ///     non-network auth-retry failures (e.g. 5xx) are NOT dropped.
  static final RegExp _offlineErrnoPattern = RegExp(
    r'errno\s*=\s*(8|50|51|65)\b',
  );

  static const List<String> _offlineMessageFragments = [
    'Failed host lookup',
    'Network is unreachable',
    'nodename nor servname provided',
    'No route to host',
  ];

  static const List<String> _networkExceptionTypes = [
    'OSError',
    'SocketException',
    'ClientException',
    'AuthRetryableFetchException',
  ];

  /// True when [error] is a transient network-availability failure
  /// (DNS/unreachable/no-route, or a plain request timeout). Call sites
  /// that probe the network on a schedule (e.g. the catalog manifest
  /// check) use this to record a breadcrumb instead of an error event —
  /// Sentry PHARMAGUIDE-14 was a manifest probe timing out on a flaky
  /// connection, which the OTA flow already handles as
  /// CatalogUnreachable.
  static bool isTransientNetworkError(Object error) {
    if (error is TimeoutException) return true;
    final text = error.toString();
    final isNetworkShaped = _networkExceptionTypes.any(text.contains);
    if (!isNetworkShaped) return false;
    return _offlineMessageFragments.any(text.contains) ||
        _offlineErrnoPattern.hasMatch(text);
  }

  static bool _isOfflineNetworkEvent(SentryEvent event) {
    final parts = <String>[
      event.message?.formatted ?? '',
      ...?event.exceptions?.map((e) => '${e.type ?? ''}: ${e.value ?? ''}'),
    ];
    final haystack = parts.join(' ');
    final isNetworkShaped = _networkExceptionTypes.any(haystack.contains);
    if (!isNetworkShaped) return false;
    return _offlineMessageFragments.any(haystack.contains) ||
        _offlineErrnoPattern.hasMatch(haystack);
  }

  @visibleForTesting
  static SentryEvent? scrubEventForTest(SentryEvent event, Hint hint) =>
      _scrubEvent(event, hint);

  static SentryEvent? _scrubEvent(SentryEvent event, Hint hint) {
    // Drop debug-only Flutter framework asserts from dev environments.
    // These assertions don't fire in release/profile builds, so they
    // only ever surface from local debug sessions that happen to have a
    // live SENTRY_DSN. Filtering at source keeps the dashboard focused
    // on issues real users actually hit.
    final env = (event.environment ?? '').toLowerCase();
    if (env == 'development' || env == 'debug') {
      final msg = event.message?.formatted ?? '';
      final excMsg =
          event.exceptions?.map((e) => e.value ?? '').join(' ') ?? '';
      final haystack = '$msg $excMsg';
      for (final pattern in _debugOnlyFrameworkAsserts) {
        if (haystack.contains(pattern)) return null;
      }
    }
    // Drop NON-FATAL network-unavailability noise (offline-first app —
    // being offline is normal, not an error). Fatal crashes always pass.
    final isFatal =
        event.level == SentryLevel.fatal || hint.get('fatal') == true;
    if (!isFatal && _isOfflineNetworkEvent(event)) {
      // Keep a cheap local/breadcrumb-level trace so a later real
      // event still shows "device was offline" context.
      CrashReportingService().log('offline: network-unavailable event dropped');
      return null;
    }
    // Scrub tags in-place.
    final tags = event.tags;
    if (tags != null) {
      for (final key in tags.keys.toList()) {
        if (_isSensitive(key)) tags[key] = '[scrubbed]';
      }
    }
    // Strip request body/headers — medical app, never exfiltrate payloads.
    final req = event.request;
    if (req != null) {
      event.request = SentryRequest(
        url: req.url,
        method: req.method,
        queryString: req.queryString,
        cookies: null,
        data: null,
        headers: const {},
      );
    }
    // Feedback events: defense in depth. captureBetaFeedback only sends a
    // synthesized, PHI-free message and never sets contact fields — but if a
    // future caller populates them, drop the PII-shaped fields here. The
    // message is kept: it's the category/impact summary, which is the signal.
    final feedback = event.contexts.feedback;
    if (feedback != null) {
      feedback.contactEmail = null;
      feedback.name = null;
    }
    return event;
  }

  static Breadcrumb? _scrubBreadcrumb(Breadcrumb? crumb, Hint hint) {
    if (crumb == null) return null;
    final data = crumb.data;
    if (data == null || data.isEmpty) return crumb;
    data
      ..clear()
      ..addAll(_scrubMap(Map<String, dynamic>.from(data)));
    return crumb;
  }

  @visibleForTesting
  void clearBuffersForTest() {
    _breadcrumbBuffer.clear();
    _errorBuffer.clear();
  }
}

class CrashBreadcrumb {
  final String message;
  final DateTime at;
  CrashBreadcrumb(this.message) : at = DateTime.now();

  @override
  String toString() => '[$at] $message';
}

class RecordedCrashError {
  final String summary;
  final StackTrace stackTrace;
  final bool fatal;
  final String? hint;
  final DateTime at;
  RecordedCrashError(this.summary, this.stackTrace, this.fatal, [this.hint])
    : at = DateTime.now();

  @override
  String toString() {
    final hintPart = hint != null ? ' [$hint]' : '';
    return '[$at] ${fatal ? "FATAL" : "non-fatal"}$hintPart $summary\n$stackTrace';
  }
}

/// Beta-feedback category. `tag` is the safe, stable value sent to Sentry as
/// `feedback.category`; `label` is the user-facing string (also used in the
/// synthesized event message). Both are PHI-free.
enum PgFeedbackCategory {
  bug('bug', 'Bug'),
  confusingResult('confusing_result', 'Confusing result'),
  wrongProductData('wrong_product_data', 'Wrong product data'),
  missingProduct('missing_product', 'Missing product'),
  featureRequest('feature_request', 'Feature request'),
  clinicalFalsePositive(
    'clinical_false_positive',
    'Medication note looks wrong',
  ),
  clinicalFalseNegative(
    'clinical_false_negative',
    'Expected medication note is missing',
  ),
  medicationNormalizationFailure(
    'clinical_identity_normalization_failure',
    "Medication wasn't recognized",
  ),
  clinicalWordingConfusion(
    'clinical_wording_confusion',
    'Medication wording is unclear',
  ),
  clinicianReportInterpretation(
    'clinician_report_interpretation',
    'Clinician report is unclear',
  ),
  searchNoResult('search_no_result', 'Search returned no result'),
  missingMedicationClassMapping(
    'clinical_class_mapping_missing',
    'Medication class looks missing',
  ),
  other('other', 'Other');

  const PgFeedbackCategory(this.tag, this.label);

  /// Safe enum value sent to Sentry.
  final String tag;

  /// User-facing label.
  final String label;
}

/// How much the issue affects the user. `tag` → Sentry, `label` → UI.
enum PgFeedbackImpact {
  blocksMe('blocks_me', 'Blocks me'),
  frustrating('frustrating', 'Frustrating'),
  minor('minor', 'Minor');

  const PgFeedbackImpact(this.tag, this.label);

  final String tag;
  final String label;
}

/// Result of a structured beta-feedback submission attempt.
enum PgFeedbackSubmissionResult {
  /// Sentry accepted the synthesized feedback event.
  sent,

  /// Sentry is not enabled for this build/session; no event was sent.
  disabled,

  /// Sentry was enabled, but capture threw.
  failed,
}
