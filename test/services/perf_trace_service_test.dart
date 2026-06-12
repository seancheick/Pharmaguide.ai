// PerfTraceService — no-throw / no-op contract.
//
// Sentry is never initialized in tests (mirrors how
// crash_reporting_service_test exercises buffer-only mode): the SDK's
// `Sentry.startTransaction` returns a no-op span when the hub is disabled,
// and the service additionally wraps every entry point in try/catch.
// These tests pin the contract that tracing can NEVER throw into the app.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/perf_trace_service.dart';

void main() {
  group('PerfTraceService — Sentry disabled (no DSN)', () {
    test('finish with no active transaction is a clean no-op', () {
      expect(() => PerfTraceService().finishScanToVerdict(), returnsNormally);
      expect(PerfTraceService().hasActiveScanToVerdict, isFalse);
    });

    test('start → finish never throws and clears the active span', () {
      final service = PerfTraceService();
      expect(service.startScanToVerdict, returnsNormally);
      expect(service.hasActiveScanToVerdict, isTrue);
      expect(() => service.finishScanToVerdict(), returnsNormally);
      expect(service.hasActiveScanToVerdict, isFalse);
    });

    test('double finish is a no-op (one-shot rebuild safety)', () {
      final service = PerfTraceService();
      service.startScanToVerdict();
      service.finishScanToVerdict();
      expect(() => service.finishScanToVerdict(), returnsNormally);
      expect(service.hasActiveScanToVerdict, isFalse);
    });

    test('restart while active abandons the old transaction, never throws', () {
      final service = PerfTraceService();
      service.startScanToVerdict();
      expect(service.startScanToVerdict, returnsNormally);
      expect(service.hasActiveScanToVerdict, isTrue);
      // Clean up so the singleton carries no state into other tests.
      service.finishScanToVerdict();
    });

    test('is a singleton (scanner and detail screen share state)', () {
      PerfTraceService().startScanToVerdict();
      expect(PerfTraceService().hasActiveScanToVerdict, isTrue);
      PerfTraceService().finishScanToVerdict();
      expect(PerfTraceService().hasActiveScanToVerdict, isFalse);
    });
    test('abandon with no active transaction is a clean no-op', () {
      expect(() => PerfTraceService().abandonScanToVerdict(), returnsNormally);
      expect(PerfTraceService().hasActiveScanToVerdict, isFalse);
    });

    test('abandon finishes the active transaction immediately', () {
      final service = PerfTraceService();
      service.startScanToVerdict();
      expect(service.hasActiveScanToVerdict, isTrue);
      expect(service.abandonScanToVerdict, returnsNormally);
      expect(service.hasActiveScanToVerdict, isFalse);
      // A finish after abandon is a no-op (verdict never rendered).
      expect(() => service.finishScanToVerdict(), returnsNormally);
      expect(service.hasActiveScanToVerdict, isFalse);
    });
  });
}
