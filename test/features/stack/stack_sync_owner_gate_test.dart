// Owner gate on the stack sync push path — belt-and-suspenders for the
// account-switch clear. Even if a clear is ever missed (crash mid-switch,
// launch race before initialSession lands), rows must NEVER upload under
// a uid that doesn't match the durable owner record.
//
// `StackSyncService._pushNow` checks `ownerAllowsPush` after resolving
// the authenticated user and skips the entire batch on mismatch.

import 'package:flutter_test/flutter_test.dart';
import 'package:pharmaguide/features/stack/services/stack_sync_queue.dart';

void main() {
  group('ownerAllowsPush', () {
    test('matching owner and current uid → push allowed', () {
      expect(ownerAllowsPush(storedOwner: 'U', currentUid: 'U'), isTrue);
    });

    test('different owner (previous user V, signed in as U) → BLOCKED', () {
      expect(ownerAllowsPush(storedOwner: 'V', currentUid: 'U'), isFalse);
    });

    test(
      'no recorded owner yet (adoption pending) → blocked until stamped',
      () {
        expect(ownerAllowsPush(storedOwner: null, currentUid: 'U'), isFalse);
        expect(ownerAllowsPush(storedOwner: '', currentUid: 'U'), isFalse);
      },
    );
  });

  test('SyncResult exposes the owner-mismatch skip state', () {
    // The service reports the skip distinctly so telemetry/debug surfaces
    // can tell "blocked cross-account push" from guest/offline skips.
    expect(SyncResult.values, contains(SyncResult.skippedOwnerMismatch));
  });
}
