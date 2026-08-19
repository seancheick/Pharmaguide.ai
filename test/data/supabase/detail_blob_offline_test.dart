// FIX (Sentry PHARMAGUIDE-1Z / PHARMAGUIDE-20): an offline device must not
// report "detail blob unavailable" as an error.
//
// Being offline is an expected state for an offline-first app. Before this
// fix, opening a product detail with no network burned the full retry budget
// (~3-5s of spinner) and emitted one error-level Sentry event per attempt —
// six events in 29 seconds on a real device during a single offline test.
//
// What must NOT change: a failed clinical fetch still throws, so no caller can
// read it as "this product has no warnings". Only the Sentry reporting and the
// wasted retries go away. Hash-verification failures — a tampered/stale-object
// signal — must keep reporting as errors.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/supabase/detail_blob_service.dart';
import 'package:pharmaguide/services/crash_reporting_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('DetailBlobUnavailableException.isOffline', () {
    test('the known-offline short circuit is classified offline', () {
      const e = DetailBlobUnavailableException(
        DetailBlobUnavailableException.offlineReason,
      );
      expect(e.isOffline, isTrue);
    });

    test('a wrapped socket failure is classified offline', () {
      final e = DetailBlobUnavailableException(
        'fetch or decoding failed',
        const SocketExceptionStub(),
      );
      // The stub is not a real SocketException, so this asserts the negative
      // case: only genuine network types count.
      expect(e.isOffline, isFalse);
    });

    test('hash-verification failure is NOT offline and still reports', () {
      const e = DetailBlobUnavailableException(
        'content hash verification failed',
      );
      expect(e.isOffline, isFalse);
    });

    test('a decode failure is NOT offline', () {
      const e = DetailBlobUnavailableException(
        'detail payload is not a JSON object',
      );
      expect(e.isOffline, isFalse);
    });
  });

  group('beforeSend drops the offline detail-blob short circuit', () {
    SentryEvent? scrub(SentryEvent e) =>
        CrashReportingService.scrubEventForTest(e, Hint());

    test('non-fatal offline detail-blob event is dropped', () {
      final result = scrub(
        SentryEvent(
          exceptions: [
            SentryException(
              type: 'DetailBlobUnavailableException',
              value:
                  'DetailBlobUnavailableException: '
                  '${DetailBlobUnavailableException.offlineReason}',
            ),
          ],
        ),
      );
      expect(result, isNull);
    });

    test('hash-verification failure is KEPT', () {
      final result = scrub(
        SentryEvent(
          exceptions: [
            SentryException(
              type: 'DetailBlobUnavailableException',
              value:
                  'DetailBlobUnavailableException: '
                  'content hash verification failed',
            ),
          ],
        ),
      );
      expect(result, isNotNull);
    });

    test('a FATAL offline event is never dropped', () {
      final result = scrub(
        SentryEvent(
          exceptions: [
            SentryException(
              type: 'DetailBlobUnavailableException',
              value:
                  'DetailBlobUnavailableException: '
                  '${DetailBlobUnavailableException.offlineReason}',
            ),
          ],
          level: SentryLevel.fatal,
        ),
      );
      expect(result, isNotNull);
    });
  });

  group('debug-only Flutter layout asserts are filtered', () {
    // Nine issues (PHARMAGUIDE-1P..1Y) reached the dashboard from ONE debug
    // simulator session on build 12. `debugAssertIsValid` cannot run in a
    // release build, so none of these can occur in production.
    SentryEvent? scrub(String value) =>
        CrashReportingService.scrubEventForTest(
          SentryEvent(
            environment: 'development',
            exceptions: [SentryException(type: 'AssertionError', value: value)],
          ),
          Hint(),
        );

    const cases = <String>[
      "'package:flutter/src/rendering/box.dart': Failed assertion: line 2251 "
          "pos 12: 'hasSize': RenderBox was not laid out: RenderPadding#dc045",
      "'package:flutter/src/rendering/object.dart': Failed assertion: line "
          "5994 pos 14: '!childSemantics.renderObject._needsLayout': is not "
          'true.',
      'BoxConstraints forces an infinite height.',
    ];

    for (var i = 0; i < cases.length; i++) {
      test('drops debug layout assert #${i + 1}', () {
        expect(scrub(cases[i]), isNull);
      });
    }

    test('a REAL non-assert error in development is kept', () {
      final result = CrashReportingService.scrubEventForTest(
        SentryEvent(
          environment: 'development',
          exceptions: [
            SentryException(type: 'StateError', value: 'Bad state: real bug'),
          ],
        ),
        Hint(),
      );
      expect(result, isNotNull);
    });
  });
}

/// Not a real SocketException — used to assert the negative case.
class SocketExceptionStub {
  const SocketExceptionStub();
}
