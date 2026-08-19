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

import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
      const e = DetailBlobUnavailableException(
        'fetch or decoding failed',
        SocketException('Network is unreachable'),
      );
      expect(e.isOffline, isTrue);
    });

    test('a wrapped HTTP client transport failure is classified offline', () {
      final e = DetailBlobUnavailableException(
        'fetch or decoding failed',
        http.ClientException(
          'ClientException with SocketException: Failed host lookup',
        ),
      );
      expect(e.isOffline, isTrue);
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

  group('detail blob retry classification', () {
    test('public access denial fails over without retrying', () {
      expect(
        detailBlobPublicFetchShouldRetry(const PublicFetchDeniedException(403)),
        isFalse,
      );
    });

    test('transport failures fail fast', () {
      expect(
        detailBlobPublicFetchShouldRetry(
          const SocketException('Network is unreachable'),
        ),
        isFalse,
      );
      expect(
        detailBlobPublicFetchShouldRetry(
          http.ClientException(
            'ClientException with SocketException: Failed host lookup',
          ),
        ),
        isFalse,
      );
    });

    test('generic client/protocol failures remain retryable', () {
      expect(
        detailBlobPublicFetchShouldRetry(
          http.ClientException('connection closed before full header'),
        ),
        isTrue,
      );
    });

    test('rate limits and server responses remain retryable', () {
      expect(
        detailBlobPublicFetchShouldRetry(
          const DetailBlobHttpStatusException(429),
        ),
        isTrue,
      );
      expect(
        detailBlobPublicFetchShouldRetry(
          const DetailBlobHttpStatusException(503),
        ),
        isTrue,
      );
    });
  });

  test('known-offline fetch does not construct a network client', () async {
    var clientFactoryCalls = 0;
    final service = DetailBlobService(
      isOffline: () => true,
      httpClientFactory: () {
        clientFactoryCalls++;
        return http.Client();
      },
    );
    CrashReportingService().clearBuffersForTest();

    await expectLater(
      service.fetchDetailBlobByHash(List.filled(64, 'a').join()),
      throwsA(
        isA<DetailBlobUnavailableException>().having(
          (error) => error.isOffline,
          'isOffline',
          isTrue,
        ),
      ),
    );

    expect(clientFactoryCalls, 0);
    expect(CrashReportingService().recordedErrors, isEmpty);
    expect(
      CrashReportingService().breadcrumbs.map((entry) => entry.message),
      contains(contains('while offline')),
    );
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
    SentryEvent? scrub(String value) => CrashReportingService.scrubEventForTest(
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
