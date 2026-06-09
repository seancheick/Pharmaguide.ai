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
      CrashReportingService().recordError(Exception('test boom'), stack);

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

  group('CrashReportingService — _isSensitive word-boundary scrubbing', () {
    // Positive set: exact match + suffix + middle. Must still scrub.
    const mustScrub = <String>[
      // Exact matches.
      'email',
      'password',
      'token',
      'auth',
      'stack',
      // Suffix on `_` boundary.
      'user_email',
      'request_token',
      'user_stack',
      // Middle on `_` boundary.
      'user_email_v2',
      'request_token_hash',
      'access_token_v3',
      'user_medications_list',
    ];

    // Negative set: keys that previously got scrubbed by the substring
    // match but carry no PII. All are `<sensitive>_<descriptor>` — that
    // prefix shape is intentionally NOT matched (see _isSensitive doc).
    const mustNotScrub = <String>[
      'email_verified',
      'condition_id_class',
      'ingredient_count',
      'medication_form',
      'stack_added_at',
      'profile_completed_at',
      'health_check_state',
      // Bare embed without `_` boundary must not match — `auth` does
      // not trip `authentication` because there is no `_` delimiter.
      'authentication',
      'preauthorized',
    ];

    for (final key in mustScrub) {
      test('scrubs sensitive key: $key', () {
        expect(CrashReportingService.isSensitiveForTest(key), isTrue);
      });
    }

    for (final key in mustNotScrub) {
      test('preserves non-sensitive key: $key', () {
        expect(CrashReportingService.isSensitiveForTest(key), isFalse);
      });
    }

    test('case-insensitive match', () {
      expect(CrashReportingService.isSensitiveForTest('EMAIL'), isTrue);
      expect(CrashReportingService.isSensitiveForTest('Access_Token'), isTrue);
      expect(
        CrashReportingService.isSensitiveForTest('Email_Verified'),
        isFalse,
      );
    });
  });
}
