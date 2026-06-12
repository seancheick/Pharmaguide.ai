import 'dart:async';

/// Coalesces rapid calls into a single deferred action.
///
/// Every [run] call within [delay] of the previous one cancels and
/// reschedules the timer; all coalesced callers share one Future that
/// completes with the result of the single action that eventually runs.
///
/// [runNow] bypasses the delay (used for `force:` paths), executing
/// immediately and completing any pending coalesced Future with the
/// same result.
class AsyncDebouncer<T> {
  AsyncDebouncer(this.delay);

  final Duration delay;

  Timer? _timer;
  Completer<T>? _pending;

  /// True when a coalesced action is scheduled but has not run yet.
  bool get isScheduled => _timer?.isActive ?? false;

  /// Schedule [action] to run after [delay]; repeated calls within the
  /// window cancel + reschedule and share the returned Future.
  ///
  /// Note: the *last* action passed wins — earlier coalesced callers get
  /// its result. Callers should pass idempotent actions (ours re-reads
  /// the dirty-row set at execution time, so this is safe).
  Future<T> run(Future<T> Function() action) {
    final completer = _pending ??= Completer<T>();
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      _pending = null;
      completer.complete(Future<T>.sync(action));
    });
    return completer.future;
  }

  /// Run [action] immediately, cancelling any scheduled run. A pending
  /// coalesced Future (from earlier [run] calls) completes with this
  /// action's result.
  Future<T> runNow(Future<T> Function() action) {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    final result = Future<T>.sync(action);
    if (pending != null) {
      pending.complete(result);
    }
    return result;
  }

  /// Cancel any scheduled run. A pending Future never completes after
  /// this — only call on teardown.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
