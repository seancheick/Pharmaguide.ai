import 'package:flutter/foundation.dart';

/// Crash reporting stub — replace with Crashlytics or Sentry in production.
///
/// Initializes without error. All methods are no-ops in this stub.
class CrashReportingService {
  static final CrashReportingService _instance = CrashReportingService._();
  factory CrashReportingService() => _instance;
  CrashReportingService._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Initialize crash reporting. Safe to call multiple times.
  Future<void> initialize() async {
    if (_initialized) return;
    // TODO: Replace with Crashlytics.instance.setCrashlyticsCollectionEnabled(true)
    // or SentryFlutter.init(...)
    _initialized = true;
    if (kDebugMode) debugPrint('CrashReportingService initialized (stub)');
  }

  /// Record a non-fatal error.
  void recordError(Object error, StackTrace stackTrace, {bool fatal = false}) {
    // TODO: Replace with Crashlytics.instance.recordError(error, stackTrace, fatal: fatal)
    if (kDebugMode) debugPrint('CrashReport: ${fatal ? "FATAL" : "non-fatal"} — $error');
  }

  /// Set a user identifier for crash context.
  void setUserId(String? userId) {
    // TODO: Replace with Crashlytics.instance.setUserIdentifier(userId ?? '')
    if (kDebugMode) debugPrint('CrashReport: userId=$userId');
  }

  /// Log a breadcrumb message.
  void log(String message) {
    // TODO: Replace with Crashlytics.instance.log(message)
    if (kDebugMode) debugPrint('CrashReport: $message');
  }
}
