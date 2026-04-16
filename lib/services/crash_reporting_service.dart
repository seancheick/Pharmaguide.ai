import 'package:flutter/foundation.dart';

/// Crash reporting facade for PharmaGuide.
///
/// ## Status
///
/// This is an intentional stub. PharmaGuide is a privacy-first, medical-grade
/// app — wiring up Crashlytics / Sentry is a product-level decision that
/// requires privacy review, DPA review, and user consent UI. Until that's
/// done, this service buffers recent breadcrumbs and errors in memory so
/// they're available during debugging, and no-ops in release builds.
///
/// ## Integration
///
/// When a backend is chosen (Crashlytics, Sentry, etc.):
///
///   1. Add the SDK dependency in `pubspec.yaml`.
///   2. In [initialize], construct the client and flush [_breadcrumbBuffer]
///      / [_errorBuffer] to it.
///   3. In [recordError] and [log], forward calls to the client when
///      available. Keep the local buffers — useful for debugging and for
///      surfacing recent context in bug reports.
///   4. Scrub the `error.toString()` output through a PII filter before it
///      leaves the device.
///
/// The public API is stable — call sites (e.g. `recordError(e, st)`) will
/// not need to change when the backend is wired up.
class CrashReportingService {
  static final CrashReportingService _instance = CrashReportingService._();
  factory CrashReportingService() => _instance;
  CrashReportingService._();

  static const int _breadcrumbMax = 100;
  static const int _errorMax = 50;

  final List<CrashBreadcrumb> _breadcrumbBuffer = <CrashBreadcrumb>[];
  final List<RecordedCrashError> _errorBuffer = <RecordedCrashError>[];

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Read-only view of recent breadcrumbs (debug tooling, tests).
  List<CrashBreadcrumb> get breadcrumbs => List.unmodifiable(_breadcrumbBuffer);

  /// Read-only view of recent errors (debug tooling, tests).
  List<RecordedCrashError> get recordedErrors => List.unmodifiable(_errorBuffer);

  /// Initialize crash reporting. Safe to call multiple times.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (kDebugMode) debugPrint('CrashReportingService initialized (stub)');
  }

  /// Record a non-fatal error.
  void recordError(Object error, StackTrace stackTrace, {bool fatal = false}) {
    _errorBuffer.add(RecordedCrashError(error.toString(), stackTrace, fatal));
    if (_errorBuffer.length > _errorMax) {
      _errorBuffer.removeRange(0, _errorBuffer.length - _errorMax);
    }
    if (kDebugMode) {
      debugPrint('CrashReport: ${fatal ? "FATAL" : "non-fatal"} — $error');
    }
  }

  /// Set a user identifier for crash context. Pass null to clear.
  void setUserId(String? userId) {
    _breadcrumbBuffer.add(CrashBreadcrumb('user_id=$userId'));
    _trimBreadcrumbs();
    if (kDebugMode) debugPrint('CrashReport: userId=$userId');
  }

  /// Log a breadcrumb message for context in future crash reports.
  void log(String message) {
    _breadcrumbBuffer.add(CrashBreadcrumb(message));
    _trimBreadcrumbs();
    if (kDebugMode) debugPrint('CrashReport: $message');
  }

  void _trimBreadcrumbs() {
    if (_breadcrumbBuffer.length > _breadcrumbMax) {
      _breadcrumbBuffer.removeRange(
        0,
        _breadcrumbBuffer.length - _breadcrumbMax,
      );
    }
  }

  /// Test-only helper to clear buffers between tests.
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
