import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

/// Scan→verdict latency instrumentation (Sentry performance tracing).
///
/// Measures the time from "barcode accepted, navigating to product detail"
/// to "hero verdict/score visible on screen" as a Sentry transaction named
/// `scan_to_verdict` (op `app.flow`).
///
/// Privacy rules (medical-grade app):
///   * NO product identifiers, barcodes, or PII — duration only.
///     (A `from_cache` tag existed briefly but was recorded before the
///     blob actually resolved, making it effectively always false —
///     junk telemetry is worse than none, so it was dropped 2026-06.)
///   * Every entry point is wrapped in try/catch so this service can NEVER
///     throw into the app. When Sentry is disabled (no DSN / placeholder),
///     `Sentry.startTransaction` returns a no-op span — every call here
///     degrades to a clean no-op.
class PerfTraceService {
  static final PerfTraceService _instance = PerfTraceService._();
  factory PerfTraceService() => _instance;
  PerfTraceService._();

  /// A scan abandoned for longer than this is finished with
  /// `deadline_exceeded` instead of polluting duration percentiles.
  static const Duration _staleDeadline = Duration(seconds: 30);

  ISentrySpan? _scanToVerdict;
  DateTime? _startedAt;

  /// True while a scan→verdict transaction is in flight. Test/diagnostic
  /// visibility only — callers should just call finish unconditionally.
  bool get hasActiveScanToVerdict => _scanToVerdict != null;

  /// Begin the scan→verdict transaction. Call at the moment a barcode is
  /// accepted and navigation to product detail begins. If a previous
  /// transaction is still active (user backed out and re-scanned), it is
  /// finished first — with `deadline_exceeded` when older than 30s,
  /// `cancelled` otherwise — and a fresh one starts.
  void startScanToVerdict() {
    try {
      final stale = _scanToVerdict;
      if (stale != null) {
        final startedAt = _startedAt;
        final isPastDeadline =
            startedAt != null &&
            DateTime.now().difference(startedAt) > _staleDeadline;
        unawaited(
          stale.finish(
            status: isPastDeadline
                ? const SpanStatus.deadlineExceeded()
                : const SpanStatus.cancelled(),
          ),
        );
      }
      _scanToVerdict = Sentry.startTransaction('scan_to_verdict', 'app.flow');
      _startedAt = DateTime.now();
      // Never let tracing break the scan flow.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      _scanToVerdict = null;
      _startedAt = null;
    }
  }

  /// Finish the scan→verdict transaction. Call once the hero verdict is
  /// visible. No-op when no transaction is active (e.g. product opened
  /// from search/stack instead of the scanner).
  void finishScanToVerdict() {
    final span = _scanToVerdict;
    _scanToVerdict = null;
    _startedAt = null;
    if (span == null) return;
    try {
      unawaited(span.finish(status: const SpanStatus.ok()));
      // Never let tracing break the detail screen.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // Swallow — instrumentation must never surface to users.
    }
  }

  /// Abandon the in-flight scan→verdict transaction, finishing it with
  /// status `cancelled` IMMEDIATELY. Call when the user backs out of the
  /// detail screen before the verdict ever rendered — otherwise the
  /// transaction dangles until the NEXT scan starts and gets finished as
  /// 'cancelled' with a junk duration spanning the whole interlude.
  /// No-op when no transaction is active.
  void abandonScanToVerdict() {
    final span = _scanToVerdict;
    _scanToVerdict = null;
    _startedAt = null;
    if (span == null) return;
    try {
      unawaited(span.finish(status: const SpanStatus.cancelled()));
      // Never let tracing break navigation.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // Swallow — instrumentation must never surface to users.
    }
  }
}
