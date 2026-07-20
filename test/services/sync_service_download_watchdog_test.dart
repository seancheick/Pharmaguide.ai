// FIX (robustness): the OTA catalog download body stream must not hang.
//
// SyncService._streamPublicDownload guards the response HEADERS with a
// 10s timeout, but `sink.addStream(response.stream)` had no timeout at
// all — a stalled connection hung that await forever, wedging the whole
// OTA subsystem for the session (including the manual retry button, since
// the caller's `_syncInFlight` flag is only cleared when the download
// returns). [inactivityWatchdogStream] is the rolling per-chunk watchdog
// now wrapped around the body stream: any inter-chunk gap longer than the
// inactivity window errors with [TimeoutException] (retryable by
// retryWithBackoff; the kept `.staging` partial Range-resumes).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/data/supabase/sync_service.dart';

void main() {
  group('inactivityWatchdogStream', () {
    test(
      'chunks flowing faster than the window pass through untouched',
      () async {
        final controller = StreamController<List<int>>();
        final out = inactivityWatchdogStream(
          controller.stream,
          inactivity: const Duration(milliseconds: 400),
        );

        final collected = <int>[];
        final done = out.forEach(collected.addAll);

        controller.add([1, 2]);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        controller.add([3]);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        controller.add([4]);
        await controller.close();
        await done;

        expect(collected, [1, 2, 3, 4]);
      },
    );

    test('a stream that never emits fails with TimeoutException', () async {
      final controller = StreamController<List<int>>();
      addTearDown(controller.close);

      final out = inactivityWatchdogStream(
        controller.stream,
        inactivity: const Duration(milliseconds: 80),
      );

      await expectLater(out.toList(), throwsA(isA<TimeoutException>()));
    });

    test('a mid-body stall errors after the delivered chunks', () async {
      final controller = StreamController<List<int>>();
      addTearDown(controller.close);

      final out = inactivityWatchdogStream(
        controller.stream,
        inactivity: const Duration(milliseconds: 100),
      );

      final collected = <int>[];
      Object? streamError;
      final done = Completer<void>();
      out.listen(
        collected.addAll,
        onError: (Object e) => streamError = e,
        onDone: done.complete,
        cancelOnError: false,
      );

      controller.add([1, 2]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      controller.add([3]);
      // …then the connection stalls: no more chunks, no close.

      await done.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail(
          'watchdog never fired — a stalled body stream would hang the '
          'OTA subsystem for the whole session',
        ),
      );

      expect(collected, [1, 2, 3], reason: 'delivered bytes are kept');
      expect(
        streamError,
        isA<TimeoutException>(),
        reason:
            'the stall must surface as a TimeoutException so '
            'retryWithBackoff retries and Range-resume continues the '
            'partial download',
      );
    });

    test(
      'watchdog closes the stream after firing (addStream terminates)',
      () async {
        // The consumer in _streamPublicDownload is IOSink.addStream, which
        // only completes when the source stream is DONE or errors — the
        // watchdog must close the stream after the error so that await
        // cannot hang.
        final controller = StreamController<List<int>>();
        addTearDown(controller.close);

        final out = inactivityWatchdogStream(
          controller.stream,
          inactivity: const Duration(milliseconds: 60),
        );

        var sawDone = false;
        Object? streamError;
        final done = Completer<void>();
        out.listen(
          (_) {},
          onError: (Object e) => streamError = e,
          onDone: () {
            sawDone = true;
            done.complete();
          },
          cancelOnError: false,
        );

        await done.future.timeout(const Duration(seconds: 5));
        expect(streamError, isA<TimeoutException>());
        expect(sawDone, isTrue);
      },
    );
  });
}
