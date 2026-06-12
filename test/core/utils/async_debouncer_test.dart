// fake_async is pinned transitively by flutter_test (Flutter SDK vendored).
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/core/utils/async_debouncer.dart';

void main() {
  group('AsyncDebouncer', () {
    test('rapid calls coalesce into a single action', () {
      fakeAsync((async) {
        final debouncer = AsyncDebouncer<int>(const Duration(seconds: 1));
        var runs = 0;
        final results = <int>[];

        for (var i = 0; i < 5; i++) {
          debouncer
              .run(() async {
                runs++;
                return runs;
              })
              .then(results.add);
          async.elapse(const Duration(milliseconds: 200));
        }

        expect(runs, 0, reason: 'still inside the debounce window');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(runs, 1, reason: '5 calls must coalesce to 1 action');
        expect(results, [
          1,
          1,
          1,
          1,
          1,
        ], reason: 'all coalesced callers share one result');
      });
    });

    test('each call within the window resets the timer', () {
      fakeAsync((async) {
        final debouncer = AsyncDebouncer<int>(const Duration(seconds: 1));
        var runs = 0;

        debouncer.run(() async => ++runs);
        async.elapse(const Duration(milliseconds: 900));
        debouncer.run(() async => ++runs); // reschedules
        async.elapse(const Duration(milliseconds: 900));
        expect(runs, 0, reason: 'second call pushed the deadline out');

        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(runs, 1);
      });
    });

    test('separate bursts produce separate runs', () {
      fakeAsync((async) {
        final debouncer = AsyncDebouncer<int>(const Duration(seconds: 1));
        var runs = 0;

        debouncer.run(() async => ++runs);
        async.elapse(const Duration(seconds: 2));
        expect(runs, 1);

        debouncer.run(() async => ++runs);
        async.elapse(const Duration(seconds: 2));
        expect(runs, 2);
      });
    });

    test('runNow executes immediately and completes pending callers', () {
      fakeAsync((async) {
        final debouncer = AsyncDebouncer<String>(const Duration(seconds: 1));
        var runs = 0;
        final results = <String>[];

        debouncer
            .run(() async {
              runs++;
              return 'debounced';
            })
            .then(results.add);

        debouncer
            .runNow(() async {
              runs++;
              return 'forced';
            })
            .then(results.add);

        async.flushMicrotasks();
        expect(runs, 1, reason: 'runNow cancels the scheduled run');
        expect(results, [
          'forced',
          'forced',
        ], reason: 'pending coalesced caller gets the forced result');

        // The cancelled debounced action never fires later.
        async.elapse(const Duration(seconds: 5));
        expect(runs, 1);
      });
    });
  });
}
