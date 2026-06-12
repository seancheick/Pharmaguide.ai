// Shared retry + backoff primitives for network/sync paths.
//
// Used by: detail_blob_service.dart (blob CDN fetch), sync_service.dart
// (manifest probe + OTA download), stack_sync_queue.dart (batched upsert),
// and main.dart (catalog refresh scheduling via [backoffDelay]).

import 'dart:async';
import 'dart:math' as math;

/// Retries [op] up to [maxAttempts] times with exponential backoff and
/// ±20% jitter between attempts.
///
/// - [baseDelay] is the delay before the second attempt; it doubles on
///   each subsequent failure (base, 2x, 4x, ...).
/// - [timeout], when set, is applied **per attempt** via `Future.timeout`,
///   so a hung attempt counts as a failure and is retried.
/// - [retryIf], when set, gates retrying: errors for which it returns
///   false are rethrown immediately (e.g. a 404 that will never succeed).
/// - [random] is injectable so tests can make the jitter deterministic.
Future<T> retryWithBackoff<T>(
  Future<T> Function() op, {
  int maxAttempts = 3,
  Duration baseDelay = const Duration(seconds: 1),
  Duration? timeout,
  bool Function(Object error)? retryIf,
  math.Random? random,
}) async {
  assert(maxAttempts >= 1, 'maxAttempts must be at least 1');
  final rng = random ?? math.Random();

  Object lastError = StateError('retryWithBackoff: no attempt ran');
  StackTrace lastStack = StackTrace.current;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final future = op();
      return await (timeout == null ? future : future.timeout(timeout));
    } on Object catch (e, st) {
      lastError = e;
      lastStack = st;
      if (retryIf != null && !retryIf(e)) {
        Error.throwWithStackTrace(e, st);
      }
      if (attempt == maxAttempts) break;
      await Future<void>.delayed(
        backoffDelay(attempt, base: baseDelay, random: rng),
      );
    }
  }

  Error.throwWithStackTrace(lastError, lastStack);
}

/// Computes the exponential-backoff delay for the given 1-based [attempt]
/// number: `base * 2^(attempt-1)`, clamped to [cap] when provided, with
/// ±[jitterFraction] uniform jitter applied (default ±20%).
Duration backoffDelay(
  int attempt, {
  required Duration base,
  Duration? cap,
  double jitterFraction = 0.2,
  math.Random? random,
}) {
  assert(attempt >= 1, 'attempt is 1-based');
  final rng = random ?? math.Random();

  var millis = base.inMilliseconds * math.pow(2, attempt - 1).toDouble();
  if (cap != null && millis > cap.inMilliseconds) {
    millis = cap.inMilliseconds.toDouble();
  }
  // Uniform jitter in [1 - f, 1 + f].
  final jitter = 1 + jitterFraction * (rng.nextDouble() * 2 - 1);
  return Duration(milliseconds: (millis * jitter).round());
}
