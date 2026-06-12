import 'dart:async';
import 'dart:math' as math;

// fake_async is pinned transitively by flutter_test (Flutter SDK vendored).
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/utils/retry.dart';

void main() {
  group('retryWithBackoff', () {
    test('returns immediately on first success (no delays)', () {
      fakeAsync((async) {
        var attempts = 0;
        String? result;
        retryWithBackoff(() async {
          attempts++;
          return 'ok';
        }).then((v) => result = v);

        async.flushMicrotasks();
        expect(attempts, 1);
        expect(result, 'ok');
      });
    });

    test('retries with exponential backoff and ±20% jitter bounds', () {
      fakeAsync((async) {
        var attempts = 0;
        String? result;
        retryWithBackoff(
          () async {
            attempts++;
            if (attempts < 3) throw Exception('transient');
            return 'ok';
          },
          baseDelay: const Duration(seconds: 1),
          random: math.Random(42),
        ).then((v) => result = v);

        async.flushMicrotasks();
        expect(attempts, 1, reason: 'first attempt runs synchronously');

        // First backoff is 1s ±20% → must NOT have fired before 0.8s...
        async.elapse(const Duration(milliseconds: 790));
        expect(attempts, 1, reason: 'jitter floor is 80% of base');
        // ...and MUST have fired by 1.2s.
        async.elapse(const Duration(milliseconds: 450));
        expect(attempts, 2);

        // Second backoff is 2s ±20% → fired by 2.4s.
        async.elapse(const Duration(milliseconds: 2400));
        expect(attempts, 3);
        async.flushMicrotasks();
        expect(result, 'ok');
      });
    });

    test('throws last error after maxAttempts exhausted', () {
      fakeAsync((async) {
        var attempts = 0;
        Object? error;
        retryWithBackoff<void>(
          () async {
            attempts++;
            throw StateError('always fails ($attempts)');
          },
          maxAttempts: 3,
          baseDelay: const Duration(milliseconds: 100),
        ).catchError((Object e) => error = e);

        async.elapse(const Duration(seconds: 5));
        expect(attempts, 3);
        expect(error, isA<StateError>());
        expect(error.toString(), contains('always fails (3)'));
      });
    });

    test('per-attempt timeout converts a hung op into a retry', () {
      fakeAsync((async) {
        var attempts = 0;
        Object? error;
        retryWithBackoff<void>(
          () {
            attempts++;
            return Completer<void>().future; // hangs forever
          },
          maxAttempts: 2,
          baseDelay: const Duration(milliseconds: 100),
          timeout: const Duration(seconds: 1),
        ).catchError((Object e) => error = e);

        async.elapse(const Duration(seconds: 10));
        expect(attempts, 2);
        expect(error, isA<TimeoutException>());
      });
    });

    test('retryIf=false rethrows immediately without retrying', () {
      fakeAsync((async) {
        var attempts = 0;
        Object? error;
        retryWithBackoff<void>(
          () async {
            attempts++;
            throw const FormatException('permanent');
          },
          maxAttempts: 5,
          retryIf: (e) => e is! FormatException,
        ).catchError((Object e) => error = e);

        async.elapse(const Duration(minutes: 1));
        expect(attempts, 1, reason: 'non-retryable errors must not retry');
        expect(error, isA<FormatException>());
      });
    });
  });

  group('backoffDelay', () {
    test('doubles per attempt within jitter bounds', () {
      final rng = math.Random(7);
      const base = Duration(minutes: 5);
      for (var attempt = 1; attempt <= 4; attempt++) {
        final expectedMs = base.inMilliseconds * math.pow(2, attempt - 1);
        final d = backoffDelay(attempt, base: base, random: rng);
        expect(
          d.inMilliseconds,
          greaterThanOrEqualTo((expectedMs * 0.8).round()),
        );
        expect(d.inMilliseconds, lessThanOrEqualTo((expectedMs * 1.2).round()));
      }
    });

    test('caps the un-jittered delay (5m base capped at 2h)', () {
      final rng = math.Random(7);
      // Attempt 7 would be 320m un-capped; cap is 120m ±20% → ≤144m.
      final d = backoffDelay(
        7,
        base: const Duration(minutes: 5),
        cap: const Duration(hours: 2),
        random: rng,
      );
      expect(d, lessThanOrEqualTo(const Duration(minutes: 144)));
      expect(d, greaterThanOrEqualTo(const Duration(minutes: 96)));
    });
  });
}
