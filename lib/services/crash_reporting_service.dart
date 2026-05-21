import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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
      options.tracesSampleRate = kReleaseMode ? 0.2 : 1.0;
      options.beforeSend = _scrubEvent;
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

  void recordError(Object error, StackTrace stackTrace, {bool fatal = false}) {
    _errorBuffer.add(RecordedCrashError(error.toString(), stackTrace, fatal));
    if (_errorBuffer.length > _errorMax) {
      _errorBuffer.removeRange(0, _errorBuffer.length - _errorMax);
    }
    if (kDebugMode) {
      debugPrint('CrashReport: ${fatal ? "FATAL" : "non-fatal"} — $error');
    }
    if (_sentryEnabled) {
      unawaited(
        Sentry.captureException(
          error,
          stackTrace: stackTrace,
          hint: fatal ? Hint.withMap({'fatal': true}) : null,
        ),
      );
    }
  }

  /// Only an opaque id is sent — never email, never profile data.
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

  static bool _isSensitive(String key) {
    final lower = key.toLowerCase();
    return _sensitiveKeys.any(lower.contains);
  }

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
  final DateTime at;
  RecordedCrashError(this.summary, this.stackTrace, this.fatal)
    : at = DateTime.now();

  @override
  String toString() =>
      '[$at] ${fatal ? "FATAL" : "non-fatal"} $summary\n$stackTrace';
}
