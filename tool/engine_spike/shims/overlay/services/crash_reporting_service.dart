// SPIKE OVERLAY for lib/services/crash_reporting_service.dart.
//
// The real service imports sentry_flutter + shared_preferences. The engine
// reaches it through lib/core/constants/severity.dart (unknown-severity drift
// report). Server-side, drift reports are collected here and surfaced in the
// spike output instead of being silently dropped. Production fix: severity.dart
// takes an injectable `void Function(Object, StackTrace, String hint)` hook.
class CrashReportingService {
  factory CrashReportingService() => _instance;
  CrashReportingService._();
  static final CrashReportingService _instance = CrashReportingService._();

  static final List<String> recorded = <String>[];

  void recordError(
    Object error,
    StackTrace stackTrace, {
    bool fatal = false,
    String? hint,
  }) {
    recorded.add('${hint ?? 'error'}: $error');
  }
}
