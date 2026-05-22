import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';

void main() {
  group('CrashReportingService — buffer-only mode', () {
    setUp(() async {
      await CrashReportingService().initialize();
      CrashReportingService().clearBuffersForTest();
    });

    test('recordError stores summary and stack trace in buffer', () {
      final stack = StackTrace.current;
      CrashReportingService().recordError(
        Exception('test boom'),
        stack,
      );

      final recorded = CrashReportingService().recordedErrors;
      expect(recorded, hasLength(1));
      expect(recorded.single.summary, contains('test boom'));
      expect(recorded.single.fatal, isFalse);
      expect(recorded.single.hint, isNull);
      expect(recorded.single.stackTrace.toString(), equals(stack.toString()));
    });

    test('recordError preserves fatal flag', () {
      CrashReportingService().recordError(
        Exception('fatal boom'),
        StackTrace.current,
        fatal: true,
      );

      expect(CrashReportingService().recordedErrors.single.fatal, isTrue);
    });

    test('recordError stores hint when provided', () {
      CrashReportingService().recordError(
        Exception('tagged boom'),
        StackTrace.current,
        hint: 'catalog_swap:path_lookup',
      );

      final recorded = CrashReportingService().recordedErrors.single;
      expect(recorded.hint, equals('catalog_swap:path_lookup'));
      // The hint surfaces in toString() so dev-mode debugPrint and the
      // local error buffer dump are useful when triaging without Sentry.
      expect(recorded.toString(), contains('[catalog_swap:path_lookup]'));
    });

    test('recordError keeps the most recent 50 entries (ring buffer)', () {
      for (var i = 0; i < 60; i++) {
        CrashReportingService().recordError(
          Exception('boom $i'),
          StackTrace.current,
        );
      }

      final recorded = CrashReportingService().recordedErrors;
      expect(recorded, hasLength(50));
      // Ring-buffer behavior: oldest entries dropped, newest kept.
      expect(recorded.first.summary, contains('boom 10'));
      expect(recorded.last.summary, contains('boom 59'));
    });

    test('log adds breadcrumb to buffer', () {
      CrashReportingService().log('test breadcrumb');

      final crumbs = CrashReportingService().breadcrumbs;
      expect(crumbs, hasLength(1));
      expect(crumbs.single.message, equals('test breadcrumb'));
    });

    test('isSentryEnabled is false in buffer-only mode', () {
      expect(CrashReportingService().isSentryEnabled, isFalse);
      expect(CrashReportingService().isInitialized, isTrue);
    });
  });

  group('CrashReportingService — RecordedCrashError', () {
    test('toString includes hint tag when present', () {
      final err = RecordedCrashError(
        'boom',
        StackTrace.current,
        true,
        'catalog_swap:open',
      );
      expect(err.toString(), contains('FATAL'));
      expect(err.toString(), contains('[catalog_swap:open]'));
      expect(err.toString(), contains('boom'));
    });

    test('toString omits hint marker when absent', () {
      final err = RecordedCrashError('boom', StackTrace.current, false);
      // The timestamp `[at]` bracket pair is always present; we just want
      // to confirm no surface-tag bracket appears next to the severity.
      expect(err.toString(), isNot(contains('non-fatal [')));
      expect(err.toString(), contains('non-fatal boom'));
    });
  });
}
